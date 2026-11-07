-- Delivery follows each phone, not just each occurrence.
--
-- 1. send-push records which phones an occurrence reached (mark_push_sent), so a
--    retry goes only to the rest, however long one phone keeps failing.
-- 2. Registration is judged per phone. A phone new to the server may have rung
--    what is due itself, so it is left out of that occurrence, and the user's
--    other phones still get it. A hidden surprise was never armed on it, so it
--    still comes.
-- 3. A dead token goes only if the row is the one the claim saw (delete_push_device
--    with p_seen), so a phone that registered again in between stays.
-- 4. A completion can't be dated in the future: acted_at stops at the moment the
--    server sees it, so a wrong clock can't silence a reminder for years.
-- 5. Changing the words of a partner's location reminder reaches the phone that
--    armed it.
-- 6. A user keeps their 10 newest phones. Evicting an old one can leave it
--    trusting the server until it next opens, so the cap sits above any real
--    household: it is only a limit on bad tokens.
--
-- Additive, so the send-push already deployed keeps working. Deploy send-push
-- after this, then apply 0021, which removes what the old one called.

alter table public.reminder_push_queue add column sent_tokens text[] not null default '{}';
alter table public.push_signals        add column sent_tokens text[] not null default '{}';

-- A new occurrence starts with no phone reached.
create or replace function public.signal_push_user(p_user uuid)
returns void
language sql
security definer set search_path = public
as $$
    insert into public.push_signals (user_id, due_at, lease_until, sent_tokens)
    select p_user, now(), null, '{}'
     where exists (select 1 from public.push_devices d where d.user_id = p_user)
    on conflict (user_id) do update
        set due_at = excluded.due_at, lease_until = null, sent_tokens = '{}';
$$;

create or replace function public.refresh_reminder_push(r public.reminders)
returns void
language plpgsql
set search_path = public
as $$
declare
    next_at timestamptz;
begin
    if public.reminder_pair_intact(r) then
        next_at := public.reminder_next_push_at(r, now(), public.push_timezone(r.target_id));
    end if;

    if next_at is null then
        delete from public.reminder_push_queue where reminder_id = r.id;
    else
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent, lease_until, sent_tokens)
        values (r.id, next_at, false, null, '{}')
        on conflict (reminder_id) do update
            set next_push_at = excluded.next_push_at, silent = false, lease_until = null, sent_tokens = '{}';
    end if;
end;
$$;

create or replace function public.sync_reminder_push(r public.reminders)
returns void
language plpgsql
set search_path = public
as $$
begin
    if public.reminder_armed_on_phone(r) then
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent, lease_until, sent_tokens)
        values (r.id, now(), true, null, '{}')
        on conflict (reminder_id) do update
            set next_push_at = now(), silent = true, lease_until = null, sent_tokens = '{}';
    else
        perform public.refresh_reminder_push(r);
    end if;
end;
$$;

-- ============================================================
-- Registration
-- ============================================================
create or replace function public.register_push_device(p_token text, p_env text, p_timezone text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    me         uuid := auth.uid();
    known_zone boolean := exists (select 1 from pg_timezone_names where name = p_timezone);
    served     boolean;
    r          public.reminders;
begin
    if me is null then
        raise exception 'not signed in';
    end if;
    if p_token is null or p_token !~ '^[0-9a-fA-F]{64,200}$' then
        raise exception 'invalid device token' using errcode = '22023';
    end if;

    served := exists (select 1 from public.push_devices where token = p_token and user_id = me);

    -- The token is the phone, so it moves when another account signs in on it,
    -- and the old account's week start does not come with it.
    insert into public.push_devices as pd (token, user_id, env, timezone, updated_at)
    values (p_token, me, p_env, case when known_zone then p_timezone else 'UTC' end, now())
    on conflict (token) do update
        set user_id       = me,
            env           = excluded.env,
            timezone      = case when known_zone then p_timezone
                                 when pd.user_id = me then pd.timezone
                                 else 'UTC' end,
            first_weekday = case when pd.user_id = me then pd.first_weekday end,
            updated_at    = now();

    delete from public.push_devices d
     where d.user_id = me
       and d.token not in (
           select x.token from public.push_devices x
            where x.user_id = me
            order by (x.token = p_token) desc, x.updated_at desc
            limit 10);

    for r in select * from public.reminders
              where target_id = me and author_id <> me and trigger_type <> 'location'
    loop
        begin
            if exists (
                select 1 from public.reminder_push_queue pq
                 where pq.reminder_id = r.id
                   and pq.next_push_at <= now()
                   and pq.next_push_at >= now() - interval '1 hour')
            then
                -- What is due and unsent stays due for the user's phones. This
                -- one rang it itself if it is new here, unless it could not see it.
                if not served and not r.surprise_hidden_from_partner then
                    update public.reminder_push_queue pq
                       set sent_tokens = array_append(pq.sent_tokens, p_token)
                     where pq.reminder_id = r.id and not (p_token = any (pq.sent_tokens));
                end if;
                continue;
            end if;
            perform public.refresh_reminder_push(r);
        exception when others then
            raise warning 'reminder push queue not updated for %: %', r.id, sqlerrm;
            delete from public.reminder_push_queue where reminder_id = r.id;
        end;
    end loop;
end;
$$;

-- ============================================================
-- Delivery, for send-push
-- ============================================================
-- Each row lists the phones still owed this occurrence. A row none are owed is over.
create or replace function public.claim_due_reminder_pushes(p_limit int default 200)
returns table (
    reminder_id   uuid,
    couple_id     uuid,
    title         text,
    body          text,
    love_language text,
    silent        boolean,
    user_id       uuid,
    due_at        timestamptz,
    devices       jsonb
)
language plpgsql
security definer set search_path = public
as $$
#variable_conflict use_column
declare
    q     public.reminder_push_queue;
    s     public.push_signals;
    r     public.reminders;
    sends boolean;
begin
    for q in
        select pq.* from public.reminder_push_queue pq
         where pq.next_push_at <= now()
           and (pq.lease_until is null or pq.lease_until <= now())
           and exists (
               select 1 from public.reminders x
                 join public.push_devices d on d.user_id = x.target_id
                where x.id = pq.reminder_id)
         order by pq.next_push_at
         limit p_limit
         for update of pq skip locked
    loop
        sends := false;
        begin
            select * into r from public.reminders x where x.id = q.reminder_id;
            devices := (select jsonb_agg(jsonb_build_object('token', d.token, 'env', d.env, 'updated_at', d.updated_at)
                                         order by d.updated_at desc)
                          from public.push_devices d
                         where d.user_id = r.target_id and d.token <> all (q.sent_tokens));
            if not public.reminder_pair_intact(r) then
                delete from public.reminder_push_queue pq where pq.reminder_id = q.reminder_id;
            elsif q.next_push_at < now() - interval '1 hour' or devices is null then
                -- Long past after an outage, or no phone is owed it any more.
                perform public.finish_reminder_push(q, r);
            elsif not q.silent
                  and public.reminder_done_at(r, public.push_timezone(r.target_id), q.next_push_at) then
                perform public.finish_reminder_push(q, r);
            else
                update public.reminder_push_queue pq
                   set lease_until = now() + interval '2 minutes'
                 where pq.reminder_id = q.reminder_id;
                sends := true;
            end if;
        exception when others then
            raise warning 'push for % left the queue: %', q.reminder_id, sqlerrm;
            delete from public.reminder_push_queue pq where pq.reminder_id = q.reminder_id;
            sends := false;
        end;

        continue when not sends;
        reminder_id   := r.id;
        couple_id     := r.couple_id;
        title         := r.title;
        body          := r.body;
        love_language := r.love_language;
        silent        := q.silent;
        user_id       := r.target_id;
        due_at        := q.next_push_at;
        return next;
    end loop;

    for s in
        select ps.* from public.push_signals ps
         where ps.due_at <= now()
           and (ps.lease_until is null or ps.lease_until <= now())
         order by ps.due_at
         limit p_limit
         for update of ps skip locked
    loop
        devices := (select jsonb_agg(jsonb_build_object('token', d.token, 'env', d.env, 'updated_at', d.updated_at)
                                     order by d.updated_at desc)
                      from public.push_devices d
                     where d.user_id = s.user_id and d.token <> all (s.sent_tokens));
        if devices is null or s.due_at < now() - interval '1 hour' then
            delete from public.push_signals ps where ps.user_id = s.user_id;
            continue;
        end if;
        update public.push_signals ps
           set lease_until = now() + interval '2 minutes'
         where ps.user_id = s.user_id;
        reminder_id   := null;
        couple_id     := null;
        title         := null;
        body          := null;
        love_language := null;
        silent        := true;
        user_id       := s.user_id;
        due_at        := s.due_at;
        return next;
    end loop;
end;
$$;

-- These phones are done with this occurrence, though another still needs a retry.
create function public.mark_push_sent(p_reminder_id uuid, p_due_at timestamptz, p_user_id uuid, p_tokens text[])
returns void
language sql
security definer set search_path = public
as $$
    update public.reminder_push_queue pq
       set sent_tokens = pq.sent_tokens || p_tokens
     where p_reminder_id is not null and pq.reminder_id = p_reminder_id and pq.next_push_at = p_due_at;
    update public.push_signals ps
       set sent_tokens = ps.sent_tokens || p_tokens
     where p_reminder_id is null and ps.user_id = p_user_id and ps.due_at = p_due_at;
$$;

create function public.delete_push_device(p_token text, p_user uuid, p_seen timestamptz)
returns void
language sql
security definer set search_path = public
as $$
    delete from public.push_devices where token = p_token and user_id = p_user and updated_at = p_seen;
$$;

-- ============================================================
-- A completion is never dated ahead of the server
-- ============================================================
create function public.reminder_events_clamp_acted_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.acted_at > now() then
        new.acted_at := now();
    end if;
    return new;
end;
$$;

create trigger reminder_events_clamp_acted_at
    before insert or update of acted_at on public.reminder_events
    for each row execute function public.reminder_events_clamp_acted_at();

update public.reminder_events set acted_at = now() where acted_at > now();

-- ============================================================
-- New words on a place the phone armed
-- ============================================================
create trigger reminders_sync_location_text
    after update of title, body, love_language on public.reminders
    for each row
    when (new.trigger_type = 'location' and (
        old.title is distinct from new.title
        or old.body is distinct from new.body
        or old.love_language is distinct from new.love_language))
    execute function public.reminders_sync_push_queue();

-- ============================================================
-- Grants
-- ============================================================
revoke all on function public.signal_push_user(uuid) from public, anon, authenticated;
revoke all on function public.refresh_reminder_push(public.reminders) from public, anon, authenticated;
revoke all on function public.sync_reminder_push(public.reminders) from public, anon, authenticated;
revoke all on function public.claim_due_reminder_pushes(int) from public, anon, authenticated;
revoke all on function public.mark_push_sent(uuid, timestamptz, uuid, text[]) from public, anon, authenticated;
revoke all on function public.delete_push_device(text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.reminder_events_clamp_acted_at() from public, anon, authenticated;
revoke all on function public.register_push_device(text, text, text) from public, anon;
grant execute on function public.register_push_device(text, text, text) to authenticated;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.claim_due_reminder_pushes(int) to service_role;
        grant execute on function public.mark_push_sent(uuid, timestamptz, uuid, text[]) to service_role;
        grant execute on function public.delete_push_device(text, uuid, timestamptz) to service_role;
    end if;
end
$$;

notify pgrst, 'reload schema';
