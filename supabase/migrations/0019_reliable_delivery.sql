-- Reliable partner delivery (council review 2026-11-06).
--
-- 1. Lease, then acknowledge. claim_due_reminder_pushes no longer moves a row on
--    before anything is sent. It leases each due row for 2 minutes and hands
--    send-push the occurrence (its due time, target and devices). send-push calls
--    ack_reminder_push once no device failed for a passing reason, and only that
--    moves the row on. A row that is not acknowledged is claimed again when its
--    lease runs out, until it is an hour late, and then moves on unsent.
-- 2. Done is decided for the occurrence's own period (its due time), not the
--    moment of the claim.
-- 3. A completion counts only when it belongs to the reminder's couple, and the
--    app can only write such completions. Reminder edits stay in the editor's
--    couple.
-- 4. One row that the schedule math cannot handle warns and leaves the queue. It
--    never stops the claim, a save, a pairing change or a registration.
-- 5. Registering again keeps occurrences that are due and not yet sent. A token
--    has to look like an APNs token, and a user keeps their 5 newest phones.
-- 6. A change to a couple's pair state, and a partner's location reminder going
--    away, send each affected phone one silent push (push_signals), so it
--    rebuilds what it armed. Pairing again re-arms location reminders too.
-- 7. A daily random reminder picks the same moment on the server as on the
--    phone (NotificationScheduler.stablePick), and one created inside today's
--    window after today's moment still comes today.

-- ============================================================
-- Values the schedule math cannot use. NOT VALID: existing rows are handled by
-- the per-row guards below, new writes are refused.
-- ============================================================
alter table public.reminders
    add constraint reminders_times_finite check (
        (fire_at is null or isfinite(fire_at))
        and (window_start is null or isfinite(window_start))
        and (window_end is null or isfinite(window_end))
    ) not valid;

-- ============================================================
-- Writes stay inside the writer's couple
-- ============================================================
-- An edit keeps the row in a couple the editor belongs to.
drop policy "reminders_author_update" on public.reminders;
create policy "reminders_author_update"
    on public.reminders for update
    using (author_id = auth.uid())
    with check (author_id = auth.uid() and public.is_couple_member(couple_id));

-- Security definer because RLS hides a surprise from its target, who can still
-- mark it done from the notification.
create function public.reminder_in_couple(p_reminder uuid, p_couple uuid)
returns boolean
language sql stable
security definer set search_path = public
as $$
    select public.is_couple_member(p_couple)
       and exists (select 1 from public.reminders where id = p_reminder and couple_id = p_couple);
$$;

drop policy "reminder_events_member_rw" on public.reminder_events;
create policy "reminder_events_member_rw"
    on public.reminder_events for all
    using (public.is_couple_member(couple_id))
    with check (public.is_couple_member(couple_id) and public.reminder_in_couple(reminder_id, couple_id));

-- leave_couple and consume_invite_code move events with their reminders, so only
-- rows written against another couple's reminder go.
delete from public.reminder_events e
 using public.reminders r
 where r.id = e.reminder_id
   and e.couple_id <> r.couple_id;

create or replace function public.reminder_done_at(r public.reminders, p_tz text, p_now timestamptz)
returns boolean
language plpgsql stable
set search_path = public
as $$
declare
    freq    text := upper(coalesce(r.rrule, ''));
    today   date := (p_now at time zone p_tz)::date;
    since   timestamptz;
    back    int;
begin
    if r.rrule is not null and r.trigger_type in ('recurring', 'random_window') then
        if r.trigger_type = 'recurring' and freq like '%FREQ=WEEKLY%' then
            back := (extract(dow from today)::int + 1 - public.push_first_weekday(r.target_id) + 7) % 7;
            since := (today - back)::timestamp at time zone p_tz;
        else
            since := date_trunc(
                case
                    when r.trigger_type = 'random_window' then 'day'
                    when freq like '%FREQ=MONTHLY%' then 'month'
                    when freq like '%FREQ=YEARLY%'  then 'year'
                    else 'day'
                end,
                p_now at time zone p_tz
            ) at time zone p_tz;
        end if;
    end if;
    return exists (
        select 1 from public.reminder_events e
        where e.reminder_id = r.id
          and e.couple_id = r.couple_id
          and e.acted_at is not null
          and (since is null or e.acted_at >= since)
    );
end;
$$;

-- ============================================================
-- Daily random: the phone's pick. FNV-1a over the reminder id (upper case, as
-- UUID.uuidString) and the day's ordinal (whole days from 1970 to the day's
-- local midnight), the same bytes NotificationScheduler.stablePick hashes.
-- ============================================================
create function public.daily_pick_unit(p_id uuid, p_day_ordinal bigint)
returns double precision
language plpgsql immutable
set search_path = public
as $$
declare
    bytes bytea := convert_to(upper(p_id::text) || p_day_ordinal::text, 'UTF8');
    h     numeric := 14695981039346656037;
    low   int;
begin
    for i in 0 .. length(bytes) - 1 loop
        low := (h % 256)::int;
        h := h - low + (low # get_byte(bytes, i));
        h := (h * 1099511628211) % 18446744073709551616;
    end loop;
    return (h % 1000000)::double precision / 1000000.0;
end;
$$;

-- The window on one local day, as instants. Minutes only, like the phone.
create function public.daily_window(
    r public.reminders, p_day date, p_tz text, out w_start timestamptz, out w_end timestamptz
)
language plpgsql stable
set search_path = public
as $$
begin
    w_start := (p_day + date_trunc('minute', r.window_start at time zone p_tz)::time) at time zone p_tz;
    w_end   := (p_day + date_trunc('minute', r.window_end   at time zone p_tz)::time) at time zone p_tz;
    if w_end <= w_start then
        w_start := null;
        w_end := null;
    end if;
end;
$$;

create or replace function public.reminder_next_push_at(r public.reminders, p_after timestamptz, p_tz text)
returns timestamptz
language plpgsql stable
set search_path = public
as $$
declare
    after_local timestamp := p_after at time zone p_tz;
    anchor      timestamp;
    candidate   timestamp;
    pick        timestamptz;
    w           record;
    lower_bound timestamptz;
    unit        double precision;
    freq        text;
    n           int;
    day         date;
begin
    if r.target_id = r.author_id or r.trigger_type = 'location' then
        return null;
    end if;

    if r.trigger_type = 'random_window' and r.rrule is not null then
        if r.window_start is null or r.window_end is null then
            return null;
        end if;
        for n in 0..1 loop
            day := after_local::date + n;
            select * into w from public.daily_window(r, day, p_tz);
            continue when w.w_start is null;
            unit := public.daily_pick_unit(
                r.id, floor(extract(epoch from day::timestamp at time zone p_tz) / 86400)::bigint
            );
            pick := w.w_start + (w.w_end - w.w_start) * unit;
            if pick > p_after then
                return pick;
            end if;
            -- Created today after today's moment, so it never came: what is
            -- left of the window, from a minute after it was made.
            if n = 0 and r.created_at > pick and (r.created_at at time zone p_tz)::date = day then
                lower_bound := r.created_at + interval '1 minute';
                if lower_bound < w.w_end then
                    pick := lower_bound + (w.w_end - lower_bound) * unit;
                    if pick > p_after then
                        return pick;
                    end if;
                end if;
            end if;
        end loop;
        return null;
    end if;

    if r.fire_at is null then
        return null;
    end if;
    if r.fire_at > p_after then
        return r.fire_at;
    end if;
    if r.trigger_type <> 'recurring' or r.rrule is null then
        return null;
    end if;

    anchor := r.fire_at at time zone p_tz;
    freq := upper(r.rrule);
    n := case
        when freq like '%FREQ=WEEKLY%'  then (after_local::date - anchor::date) / 7
        when freq like '%FREQ=MONTHLY%' then (extract(year from age(after_local, anchor)) * 12
                                              + extract(month from age(after_local, anchor)))::int
        when freq like '%FREQ=YEARLY%'  then extract(year from age(after_local, anchor))::int
        else after_local::date - anchor::date
    end;
    loop
        candidate := anchor + case
            when freq like '%FREQ=WEEKLY%'  then n * interval '7 days'
            when freq like '%FREQ=MONTHLY%' then n * interval '1 month'
            when freq like '%FREQ=YEARLY%'  then n * interval '1 year'
            else n * interval '1 day'
        end;
        if (candidate at time zone p_tz) > p_after then
            return candidate at time zone p_tz;
        end if;
        n := n + 1;
    end loop;
end;
$$;

-- ============================================================
-- Queue leases and phone signals
-- ============================================================
alter table public.reminder_push_queue add column lease_until timestamptz;

-- One pending "rebuild what you armed" push per user. No policies: only the
-- security definer functions and the service role touch it.
create table public.push_signals (
    user_id     uuid primary key references public.profiles(id) on delete cascade,
    due_at      timestamptz not null default now(),
    lease_until timestamptz
);
alter table public.push_signals enable row level security;
revoke all on table public.push_signals from anon, authenticated;

create function public.signal_push_user(p_user uuid)
returns void
language sql
security definer set search_path = public
as $$
    insert into public.push_signals (user_id, due_at, lease_until)
    select p_user, now(), null
     where exists (select 1 from public.push_devices d where d.user_id = p_user)
    on conflict (user_id) do update set due_at = excluded.due_at, lease_until = null;
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
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent, lease_until)
        values (r.id, next_at, false, null)
        on conflict (reminder_id) do update
            set next_push_at = excluded.next_push_at, silent = false, lease_until = null;
    end if;
end;
$$;

-- Whether the target's phone arms this reminder itself once the server delivers:
-- a partner's visible location reminder.
create function public.reminder_armed_on_phone(r public.reminders)
returns boolean
language sql stable
set search_path = public
as $$
    select r.trigger_type = 'location'
       and r.target_id <> r.author_id
       and not r.surprise_hidden_from_partner
       and public.reminder_pair_intact(r);
$$;

-- Queues one reminder's next push: a silent one for a place, so the phone arms it.
create function public.sync_reminder_push(r public.reminders)
returns void
language plpgsql
set search_path = public
as $$
begin
    if public.reminder_armed_on_phone(r) then
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent, lease_until)
        values (r.id, now(), true, null)
        on conflict (reminder_id) do update set next_push_at = now(), silent = true, lease_until = null;
    else
        perform public.refresh_reminder_push(r);
    end if;
end;
$$;

-- A failure here must never cost anyone a save. The row leaves the queue rather
-- than keep a time that no longer matches the reminder.
create or replace function public.reminders_sync_push_queue()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    begin
        perform public.sync_reminder_push(new);
    exception when others then
        raise warning 'reminder push queue not updated for %: %', new.id, sqlerrm;
        delete from public.reminder_push_queue where reminder_id = new.id;
    end;
    -- A place the old target's phone armed, now gone from it.
    if tg_op = 'UPDATE' then
        begin
            if public.reminder_armed_on_phone(old)
               and (new.target_id <> old.target_id or not public.reminder_armed_on_phone(new)) then
                perform public.signal_push_user(old.target_id);
            end if;
        exception when others then
            raise warning 'phone not signalled for %: %', new.id, sqlerrm;
        end;
    end if;
    return new;
end;
$$;

create function public.reminders_signal_on_delete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    if public.reminder_armed_on_phone(old) then
        perform public.signal_push_user(old.target_id);
    end if;
    return old;
exception when others then
    raise warning 'phone not signalled for deleted %: %', old.id, sqlerrm;
    return old;
end;
$$;

create trigger reminders_signal_on_delete
    after delete on public.reminders
    for each row execute function public.reminders_signal_on_delete();

-- A failure here must never cost anyone an unpair or a pairing.
create or replace function public.couples_sync_push_queue()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
    r public.reminders;
    u uuid;
begin
    if old.partner_a is not distinct from new.partner_a
       and old.partner_b is not distinct from new.partner_b
       and old.solo is not distinct from new.solo then
        return new;
    end if;
    for r in
        select * from public.reminders x
         where x.couple_id = new.id and x.author_id <> x.target_id
    loop
        begin
            perform public.sync_reminder_push(r);
        exception when others then
            raise warning 'reminder push queue not updated for %: %', r.id, sqlerrm;
            delete from public.reminder_push_queue where reminder_id = r.id;
        end;
    end loop;
    -- Everyone on either side rebuilds what their phone armed.
    foreach u in array array[old.partner_a, old.partner_b, new.partner_a, new.partner_b] loop
        begin
            perform public.signal_push_user(u);
        exception when others then
            raise warning 'phone not signalled for %: %', u, sqlerrm;
        end;
    end loop;
    return new;
exception when others then
    raise warning 'reminder push queue not updated for couple %: %', new.id, sqlerrm;
    return new;
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
    had_device boolean;
    r          public.reminders;
begin
    if me is null then
        raise exception 'not signed in';
    end if;
    if p_token is null or p_token !~ '^[0-9a-fA-F]{64,200}$' then
        raise exception 'invalid device token' using errcode = '22023';
    end if;

    -- A phone already served by the server has nothing armed for these
    -- reminders, so what is due and unsent stays due. A first phone rang them
    -- itself.
    had_device := exists (select 1 from public.push_devices where user_id = me);

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
            limit 5);

    for r in select * from public.reminders
              where target_id = me and author_id <> me and trigger_type <> 'location'
    loop
        begin
            continue when had_device and exists (
                select 1 from public.reminder_push_queue pq
                 where pq.reminder_id = r.id
                   and pq.next_push_at <= now()
                   and pq.next_push_at >= now() - interval '1 hour');
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
-- What happens to a row once its occurrence is over: sent, done, or too late.
create function public.finish_reminder_push(q public.reminder_push_queue, r public.reminders)
returns void
language plpgsql
set search_path = public
as $$
begin
    if q.silent or r.id is null then
        delete from public.reminder_push_queue where reminder_id = q.reminder_id;
    else
        perform public.refresh_reminder_push(r);
    end if;
end;
$$;

drop function public.claim_due_reminder_pushes(int);

-- A signal row comes back with no reminder. Everything returned is leased, and
-- comes back again after 2 minutes unless ack_reminder_push said it was sent.
create function public.claim_due_reminder_pushes(p_limit int default 200)
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
            if not public.reminder_pair_intact(r) then
                delete from public.reminder_push_queue pq where pq.reminder_id = q.reminder_id;
            elsif q.next_push_at < now() - interval '1 hour' then
                -- After an outage, skip what is long past rather than burst it.
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
        devices       := (select jsonb_agg(jsonb_build_object('token', d.token, 'env', d.env)
                                           order by d.updated_at desc)
                            from public.push_devices d where d.user_id = r.target_id);
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
        devices := (select jsonb_agg(jsonb_build_object('token', d.token, 'env', d.env)
                                     order by d.updated_at desc)
                      from public.push_devices d where d.user_id = s.user_id);
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

-- Sent. Moves the occurrence on, unless the row has moved since the claim (an
-- edit, a newer signal), which keeps the newer one.
create function public.ack_reminder_push(p_reminder_id uuid, p_due_at timestamptz, p_user_id uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    q public.reminder_push_queue;
    r public.reminders;
begin
    if p_reminder_id is null then
        delete from public.push_signals where user_id = p_user_id and due_at = p_due_at;
        return;
    end if;

    select * into q from public.reminder_push_queue
     where reminder_id = p_reminder_id and next_push_at = p_due_at
     for update;
    if not found then
        return;
    end if;
    select * into r from public.reminders where id = p_reminder_id;
    begin
        perform public.finish_reminder_push(q, r);
    exception when others then
        raise warning 'push for % left the queue: %', p_reminder_id, sqlerrm;
        delete from public.reminder_push_queue where reminder_id = p_reminder_id;
    end;
end;
$$;

-- A dead token goes only while it still belongs to the user it was claimed for.
create function public.delete_push_device(p_token text, p_user uuid)
returns void
language sql
security definer set search_path = public
as $$
    delete from public.push_devices where token = p_token and user_id = p_user;
$$;

-- ============================================================
-- APNs provider token, shared by every send-push instance: Apple refuses a key
-- whose token changes too often.
-- ============================================================
create table public.apns_provider_tokens (
    key_id    text primary key,
    token     text not null,
    issued_at timestamptz not null
);
alter table public.apns_provider_tokens enable row level security;
revoke all on table public.apns_provider_tokens from anon, authenticated;

create function public.get_apns_provider_token(p_key_id text)
returns table (token text, issued_at timestamptz)
language sql stable
security definer set search_path = public
as $$
    select t.token, t.issued_at from public.apns_provider_tokens t where t.key_id = p_key_id;
$$;

create function public.put_apns_provider_token(p_key_id text, p_token text, p_issued_at timestamptz)
returns void
language sql
security definer set search_path = public
as $$
    insert into public.apns_provider_tokens (key_id, token, issued_at)
    values (p_key_id, p_token, p_issued_at)
    on conflict (key_id) do update set token = excluded.token, issued_at = excluded.issued_at;
$$;

-- ============================================================
-- Grants. Supabase grants new public functions to anon, authenticated and
-- service_role by name, so every function here is closed explicitly.
-- ============================================================
revoke all on function public.reminder_in_couple(uuid, uuid) from public, anon, authenticated;
grant execute on function public.reminder_in_couple(uuid, uuid) to authenticated;

revoke all on function public.reminder_done_at(public.reminders, text, timestamptz) from public, anon, authenticated;
revoke all on function public.daily_pick_unit(uuid, bigint) from public, anon, authenticated;
revoke all on function public.daily_window(public.reminders, date, text) from public, anon, authenticated;
revoke all on function public.reminder_next_push_at(public.reminders, timestamptz, text) from public, anon, authenticated;
revoke all on function public.signal_push_user(uuid) from public, anon, authenticated;
revoke all on function public.refresh_reminder_push(public.reminders) from public, anon, authenticated;
revoke all on function public.reminder_armed_on_phone(public.reminders) from public, anon, authenticated;
revoke all on function public.sync_reminder_push(public.reminders) from public, anon, authenticated;
revoke all on function public.reminders_sync_push_queue() from public, anon, authenticated;
revoke all on function public.reminders_signal_on_delete() from public, anon, authenticated;
revoke all on function public.couples_sync_push_queue() from public, anon, authenticated;
revoke all on function public.finish_reminder_push(public.reminder_push_queue, public.reminders) from public, anon, authenticated;
revoke all on function public.claim_due_reminder_pushes(int) from public, anon, authenticated;
revoke all on function public.ack_reminder_push(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.delete_push_device(text, uuid) from public, anon, authenticated;
revoke all on function public.get_apns_provider_token(text) from public, anon, authenticated;
revoke all on function public.put_apns_provider_token(text, text, timestamptz) from public, anon, authenticated;

revoke all on function public.register_push_device(text, text, text) from public, anon;
grant execute on function public.register_push_device(text, text, text) to authenticated;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.claim_due_reminder_pushes(int) to service_role;
        grant execute on function public.ack_reminder_push(uuid, timestamptz, uuid) to service_role;
        grant execute on function public.delete_push_device(text, uuid) to service_role;
        grant execute on function public.get_apns_provider_token(text) to service_role;
        grant execute on function public.put_apns_provider_token(text, text, timestamptz) to service_role;
    end if;
end
$$;

-- ============================================================
-- Schedule: wake send-push for leased-out rows that came back and for signals
-- too. Same Vault secrets as 0014. Guarded for scripts/test-db.sh.
-- ============================================================
do $$
begin
    if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        raise notice 'pg_cron not available; skipping schedule';
        return;
    end if;
    create extension if not exists pg_cron;
    create extension if not exists pg_net;

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
            timeout_milliseconds := 20000
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
