-- Delivery details found on review of 0020.
--
-- 1. The phone says whether it armed anything itself (p_armed_locally), since a
--    served phone with a new token looks new to the server and had armed nothing.
-- 2. A claim returns up to p_limit rows to send. Rows it finishes without sending
--    no longer use up the limit, so send-push can tell when it has run out.
-- 3. An ack names the phones it covers. A phone that registered during the send
--    is still owed the occurrence, so the row stays for it.
-- 4. Removing a dead token says whether it went. A phone that registered again
--    during the send stays, and is still owed the occurrence.
-- 5. A completion up to 5 minutes ahead of the server keeps its date. Phone clocks
--    run a little fast, and moving it can put it in the period before midnight.
-- 6. The cron request waits for send-push rather than dropping after 20 seconds.
--
-- Additive, so the send-push already deployed keeps working. Deploy send-push
-- after this, then apply 0023, which removes what the old one called.

-- ============================================================
-- Registration
-- ============================================================
create function public.push_register(p_token text, p_env text, p_timezone text, p_armed_locally boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    me         uuid := auth.uid();
    known_zone boolean := exists (select 1 from pg_timezone_names where name = p_timezone);
    armed      boolean;
    r          public.reminders;
begin
    if me is null then
        raise exception 'not signed in';
    end if;
    if p_token is null or p_token !~ '^[0-9a-fA-F]{64,200}$' then
        raise exception 'invalid device token' using errcode = '22023';
    end if;

    -- A build that does not say: a phone new to the server armed its own.
    armed := coalesce(
        p_armed_locally,
        not exists (select 1 from public.push_devices where token = p_token and user_id = me)
    );

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
                -- one rang it itself if it armed it, and it can't arm a surprise.
                if armed and not r.surprise_hidden_from_partner then
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

create or replace function public.register_push_device(p_token text, p_env text, p_timezone text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
    perform public.push_register(p_token, p_env, p_timezone, null);
end;
$$;

create function public.register_push_device(
    p_token text, p_env text, p_timezone text, p_first_weekday int, p_armed_locally boolean
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
    perform public.push_register(p_token, p_env, p_timezone, p_armed_locally);
    update public.push_devices
       set first_weekday = case when p_first_weekday between 1 and 7 then p_first_weekday end
     where token = p_token and user_id = auth.uid();
end;
$$;

-- ============================================================
-- Delivery, for send-push
-- ============================================================
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
    q        public.reminder_push_queue;
    s        public.push_signals;
    r        public.reminders;
    sends    boolean;
    returned int := 0;
    -- Rows finished unsent leave the queue, so this only bounds one call.
    examined int := 0;
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
         for update of pq skip locked
    loop
        examined := examined + 1;
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

        if sends then
            reminder_id   := r.id;
            couple_id     := r.couple_id;
            title         := r.title;
            body          := r.body;
            love_language := r.love_language;
            silent        := q.silent;
            user_id       := r.target_id;
            due_at        := q.next_push_at;
            return next;
            returned := returned + 1;
        end if;
        exit when returned >= p_limit or examined >= p_limit * 20;
    end loop;

    returned := 0;
    examined := 0;
    for s in
        select ps.* from public.push_signals ps
         where ps.due_at <= now()
           and (ps.lease_until is null or ps.lease_until <= now())
         order by ps.due_at
         for update of ps skip locked
    loop
        examined := examined + 1;
        devices := (select jsonb_agg(jsonb_build_object('token', d.token, 'env', d.env, 'updated_at', d.updated_at)
                                     order by d.updated_at desc)
                      from public.push_devices d
                     where d.user_id = s.user_id and d.token <> all (s.sent_tokens));
        if devices is null or s.due_at < now() - interval '1 hour' then
            delete from public.push_signals ps where ps.user_id = s.user_id;
        else
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
            returned := returned + 1;
        end if;
        exit when returned >= p_limit or examined >= p_limit * 20;
    end loop;
end;
$$;

-- These phones are done. The occurrence is over unless a phone registered since
-- the claim, which is still owed it.
create function public.ack_reminder_push(p_reminder_id uuid, p_due_at timestamptz, p_user_id uuid, p_tokens text[])
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    q    public.reminder_push_queue;
    s    public.push_signals;
    r    public.reminders;
begin
    if p_reminder_id is null then
        select * into s from public.push_signals where user_id = p_user_id and due_at = p_due_at for update;
        if not found then
            return;
        end if;
        if exists (select 1 from public.push_devices d
                    where d.user_id = p_user_id and d.token <> all (s.sent_tokens || p_tokens)) then
            update public.push_signals
               set sent_tokens = s.sent_tokens || p_tokens, lease_until = null
             where user_id = p_user_id;
        else
            delete from public.push_signals where user_id = p_user_id;
        end if;
        return;
    end if;

    select * into q from public.reminder_push_queue
     where reminder_id = p_reminder_id and next_push_at = p_due_at
     for update;
    if not found then
        return;
    end if;
    select * into r from public.reminders where id = p_reminder_id;
    if exists (select 1 from public.push_devices d
                where d.user_id = r.target_id and d.token <> all (q.sent_tokens || p_tokens)) then
        update public.reminder_push_queue
           set sent_tokens = q.sent_tokens || p_tokens, lease_until = null
         where reminder_id = p_reminder_id;
        return;
    end if;
    begin
        perform public.finish_reminder_push(q, r);
    exception when others then
        raise warning 'push for % left the queue: %', p_reminder_id, sqlerrm;
        delete from public.reminder_push_queue where reminder_id = p_reminder_id;
    end;
end;
$$;

create function public.remove_dead_push_device(p_token text, p_user uuid, p_seen timestamptz)
returns boolean
language sql
security definer set search_path = public
as $$
    with gone as (
        delete from public.push_devices
         where token = p_token and user_id = p_user and updated_at = p_seen
        returning 1
    )
    select exists (select 1 from gone);
$$;

-- ============================================================
-- A completion a little ahead of the server keeps its date
-- ============================================================
create or replace function public.reminder_events_clamp_acted_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.acted_at > now() + interval '5 minutes' then
        new.acted_at := now();
    end if;
    return new;
end;
$$;

-- ============================================================
-- Grants
-- ============================================================
revoke all on function public.push_register(text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.claim_due_reminder_pushes(int) from public, anon, authenticated;
revoke all on function public.ack_reminder_push(uuid, timestamptz, uuid, text[]) from public, anon, authenticated;
revoke all on function public.remove_dead_push_device(text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.reminder_events_clamp_acted_at() from public, anon, authenticated;
revoke all on function public.register_push_device(text, text, text) from public, anon;
grant execute on function public.register_push_device(text, text, text) to authenticated;
revoke all on function public.register_push_device(text, text, text, int, boolean) from public, anon;
grant execute on function public.register_push_device(text, text, text, int, boolean) to authenticated;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.claim_due_reminder_pushes(int) to service_role;
        grant execute on function public.ack_reminder_push(uuid, timestamptz, uuid, text[]) to service_role;
        grant execute on function public.remove_dead_push_device(text, uuid, timestamptz) to service_role;
    end if;
end
$$;

-- ============================================================
-- Schedule: the same job, waiting as long as a run can take.
-- ============================================================
do $$
begin
    if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        raise notice 'pg_cron not available; skipping schedule';
        return;
    end if;
    perform cron.unschedule('bond-send-push')
      where exists (select 1 from cron.job where jobname = 'bond-send-push');

    perform cron.schedule(
        'bond-send-push',
        '* * * * *',
        $job$
        select net.http_post(
            url := (select decrypted_secret from vault.decrypted_secrets where name = 'send_push_url'),
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                                where name = 'send_push_secret')
            ),
            body := '{}'::jsonb,
            timeout_milliseconds := 145000
        )
        where exists (
            select 1 from public.reminder_push_queue pq
              join public.reminders r on r.id = pq.reminder_id
              join public.push_devices d on d.user_id = r.target_id
             where pq.next_push_at <= now()
               and (pq.lease_until is null or pq.lease_until <= now())
        )
        or exists (
            select 1 from public.push_signals ps
             where ps.due_at <= now()
               and (ps.lease_until is null or ps.lease_until <= now())
        );
        $job$
    );
end
$$;

notify pgrst, 'reload schema';
