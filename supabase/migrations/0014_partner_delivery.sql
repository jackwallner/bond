-- Partner delivery. Two bugs from the 2026-10-31 hunt:
--
-- 1. The target of a partner's reminder could not move or remove it: the RLS
--    policies only let the author write. reschedule_reminder and a target delete
--    policy fix that. The rest of the row stays the author's, so the RPC writes
--    the schedule columns only.
--
-- 2. A reminder written for the partner only reached their phone if their app
--    ran before it was due, and a surprise, which RLS hides from them, never did.
--    The server now owns the time of partner-written reminders. A trigger keeps
--    reminder_push_queue current, pg_cron wakes send-push when something is due,
--    and claim_due_reminder_pushes hands it the pushes and moves each row on.
--
-- A phone only stops arming these locally after register_push_device succeeded,
-- so app versions without push, and Android, keep their local notifications and
-- never get a second copy. Location reminders still arm on the device, because
-- only it knows where it is: they get one silent push so it can.

-- ============================================================
-- Devices. Separate from profiles because partners can read each other's profile,
-- and one person can have two phones.
-- ============================================================
create table public.push_devices (
    token      text primary key,
    user_id    uuid not null references public.profiles(id) on delete cascade,
    env        text not null check (env in ('production', 'sandbox')),
    timezone   text not null default 'UTC',
    updated_at timestamptz not null default now()
);

create index push_devices_user_idx on public.push_devices(user_id);

alter table public.push_devices enable row level security;
-- No policies: clients go through the two RPCs below.

-- ============================================================
-- The queue. Separate from reminders so that moving it on does not send a
-- realtime change to both partners on every delivery.
-- ============================================================
create table public.reminder_push_queue (
    reminder_id  uuid primary key references public.reminders(id) on delete cascade,
    next_push_at timestamptz not null,
    silent       boolean not null default false
);

create index reminder_push_queue_due_idx on public.reminder_push_queue(next_push_at);

alter table public.reminder_push_queue enable row level security;
-- No policies: only the security definer functions and the service role touch it.

-- ============================================================
-- The next delivery after a moment, in the target's time zone so "every day at
-- 8" stays at 8 across daylight saving. Mirrors NotificationScheduler.
-- ============================================================
create function public.reminder_next_push_at(r public.reminders, p_after timestamptz, p_tz text)
returns timestamptz
language plpgsql stable
set search_path = public
as $$
declare
    after_local timestamp := p_after at time zone p_tz;
    anchor      timestamp;
    candidate   timestamp;
    freq        text;
    n           int;
    day         date;
    ws          time;
    we          time;
    unit        double precision;
begin
    if r.target_id = r.author_id or r.trigger_type = 'location' then
        return null;
    end if;

    -- Daily random window: a stable pick per day, as stablePick does on device.
    if r.trigger_type = 'random_window' and r.rrule is not null then
        if r.window_start is null or r.window_end is null then
            return null;
        end if;
        ws := (r.window_start at time zone p_tz)::time;
        we := (r.window_end at time zone p_tz)::time;
        if we <= ws then
            return null;
        end if;
        for n in 0..1 loop
            day := after_local::date + n;
            unit := (abs(hashtext(r.id::text || day::text)) % 1000000) / 1000000.0;
            candidate := (day + ws) + (we - ws) * unit;
            if (candidate at time zone p_tz) > p_after then
                return candidate at time zone p_tz;
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
    -- Whole steps from the anchor, so a monthly on the 31st clamps per month
    -- and does not drift to the 28th for good.
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

-- Whether marking it done should silence this delivery. Mirrors ReminderCompletion:
-- a repeating reminder is done for its current period, any other for good.
create function public.reminder_done_now(r public.reminders, p_tz text)
returns boolean
language plpgsql stable
set search_path = public
as $$
declare
    freq  text := upper(coalesce(r.rrule, ''));
    since timestamptz;
begin
    if r.rrule is not null and r.trigger_type in ('recurring', 'random_window') then
        since := date_trunc(
            case
                when r.trigger_type = 'random_window' then 'day'
                when freq like '%FREQ=WEEKLY%'  then 'week'
                when freq like '%FREQ=MONTHLY%' then 'month'
                when freq like '%FREQ=YEARLY%'  then 'year'
                else 'day'
            end,
            now() at time zone p_tz
        ) at time zone p_tz;
    end if;
    return exists (
        select 1 from public.reminder_events e
        where e.reminder_id = r.id
          and e.acted_at is not null
          and (since is null or e.acted_at >= since)
    );
end;
$$;

create function public.push_timezone(p_user uuid)
returns text
language sql stable
set search_path = public
as $$
    select coalesce(
        (select timezone from public.push_devices
          where user_id = p_user order by updated_at desc limit 1),
        'UTC'
    );
$$;

-- Puts one reminder's next delivery in the queue, or takes it out.
create function public.refresh_reminder_push(r public.reminders)
returns void
language plpgsql
set search_path = public
as $$
declare
    next_at timestamptz := public.reminder_next_push_at(r, now(), public.push_timezone(r.target_id));
begin
    if next_at is null then
        delete from public.reminder_push_queue where reminder_id = r.id;
    else
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent)
        values (r.id, next_at, false)
        on conflict (reminder_id) do update
            set next_push_at = excluded.next_push_at, silent = false;
    end if;
end;
$$;

-- A failure here must never cost anyone a save, so it warns and moves on.
create function public.reminders_sync_push_queue()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    if new.trigger_type = 'location'
       and new.target_id <> new.author_id
       and not new.surprise_hidden_from_partner then
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent)
        values (new.id, now(), true)
        on conflict (reminder_id) do update set next_push_at = now(), silent = true;
    else
        perform public.refresh_reminder_push(new);
    end if;
    return new;
exception when others then
    raise warning 'reminder push queue not updated for %: %', new.id, sqlerrm;
    return new;
end;
$$;

create trigger reminders_sync_push_queue
    after insert or update of fire_at, rrule, geofence, window_start, window_end,
        trigger_type, author_id, target_id, surprise_hidden_from_partner
    on public.reminders
    for each row execute function public.reminders_sync_push_queue();

-- Rows from before this migration.
select public.refresh_reminder_push(r) from public.reminders r where r.author_id <> r.target_id;

-- ============================================================
-- Client RPCs
-- ============================================================
create function public.register_push_device(p_token text, p_env text, p_timezone text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    me uuid := auth.uid();
    tz text := case when exists (select 1 from pg_timezone_names where name = p_timezone)
                    then p_timezone else 'UTC' end;
    r  public.reminders;
begin
    if me is null then
        raise exception 'not signed in';
    end if;
    -- The token is the phone, so it moves when another account signs in on it.
    insert into public.push_devices (token, user_id, env, timezone, updated_at)
    values (p_token, me, p_env, tz, now())
    on conflict (token) do update
        set user_id = me, env = excluded.env, timezone = excluded.timezone, updated_at = now();

    -- Anything already due is the past now, and the times may have a new zone.
    for r in select * from public.reminders
              where target_id = me and author_id <> me and trigger_type <> 'location'
    loop
        perform public.refresh_reminder_push(r);
    end loop;
end;
$$;

create function public.unregister_push_device(p_token text)
returns void
language sql
security definer set search_path = public
as $$
    delete from public.push_devices where token = p_token and user_id = auth.uid();
$$;

-- What the target of a partner's reminder may change: when it comes. Hidden rows
-- stay out of reach, as they are from every other read and write.
create function public.reschedule_reminder(
    p_id uuid,
    p_trigger_type text,
    p_fire_at timestamptz,
    p_rrule text,
    p_geofence jsonb,
    p_window_start timestamptz,
    p_window_end timestamptz
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
    update public.reminders
       set trigger_type = p_trigger_type,
           fire_at      = p_fire_at,
           rrule        = p_rrule,
           geofence     = p_geofence,
           window_start = p_window_start,
           window_end   = p_window_end
     where id = p_id
       and target_id = auth.uid()
       and not surprise_hidden_from_partner
       and public.is_couple_member(couple_id);
    if not found then
        raise exception 'reminder not found' using errcode = 'P0002';
    end if;
end;
$$;

create policy "reminders_target_delete"
    on public.reminders for delete
    using (target_id = auth.uid() and not surprise_hidden_from_partner);

-- ============================================================
-- Delivery, for send-push. Moving a row on before the push is sent means a crash
-- loses one delivery and can never repeat one forever.
-- ============================================================
create function public.claim_due_reminder_pushes(p_limit int default 200)
returns table (
    reminder_id   uuid,
    couple_id     uuid,
    title         text,
    body          text,
    love_language text,
    silent        boolean,
    token         text,
    env           text
)
language plpgsql
security definer set search_path = public
as $$
declare
    q  public.reminder_push_queue;
    r  public.reminders;
    tz text;
    stale boolean;
begin
    for q in
        select pq.* from public.reminder_push_queue pq
         where pq.next_push_at <= now()
           and exists (
               select 1 from public.reminders x
                 join public.push_devices d on d.user_id = x.target_id
                where x.id = pq.reminder_id)
         order by pq.next_push_at
         limit p_limit
         for update of pq skip locked
    loop
        select * into r from public.reminders x where x.id = q.reminder_id;
        tz := public.push_timezone(r.target_id);
        -- After an outage, skip what is long past rather than burst it.
        stale := q.next_push_at < now() - interval '1 hour';

        if not stale and (q.silent or not public.reminder_done_now(r, tz)) then
            return query
                select r.id, r.couple_id, r.title, r.body, r.love_language, q.silent, d.token, d.env
                  from public.push_devices d
                 where d.user_id = r.target_id;
        end if;

        if q.silent then
            delete from public.reminder_push_queue pq where pq.reminder_id = r.id;
        else
            perform public.refresh_reminder_push(r);
        end if;
    end loop;
end;
$$;

create function public.delete_push_device(p_token text)
returns void
language sql
security definer set search_path = public
as $$
    delete from public.push_devices where token = p_token;
$$;

-- ============================================================
-- Grants. Functions are executable by PUBLIC until revoked.
-- ============================================================
revoke all on function public.reminder_next_push_at(public.reminders, timestamptz, text) from public;
revoke all on function public.reminder_done_now(public.reminders, text) from public;
revoke all on function public.push_timezone(uuid) from public;
revoke all on function public.refresh_reminder_push(public.reminders) from public;
revoke all on function public.reminders_sync_push_queue() from public;
revoke all on function public.claim_due_reminder_pushes(int) from public;
revoke all on function public.delete_push_device(text) from public;
revoke all on function public.register_push_device(text, text, text) from public;
revoke all on function public.unregister_push_device(text) from public;
revoke all on function public.reschedule_reminder(uuid, text, timestamptz, text, jsonb, timestamptz, timestamptz) from public;

grant execute on function public.register_push_device(text, text, text) to authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;
grant execute on function public.reschedule_reminder(uuid, text, timestamptz, text, jsonb, timestamptz, timestamptz) to authenticated;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.claim_due_reminder_pushes(int) to service_role;
        grant execute on function public.delete_push_device(text) to service_role;
    end if;
end
$$;

-- ============================================================
-- Schedule. Guarded because scripts/test-db.sh runs on a bare Postgres. Only calls
-- the function when something can be delivered, so an idle minute costs nothing.
--
-- Vault secrets, set once outside the repo:
--   send_push_url     https://<ref>.supabase.co/functions/v1/send-push
--   send_push_secret  same value as the function's PUSH_CRON_SECRET
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
        );
        $job$
    );
end
$$;

notify pgrst, 'reload schema';
