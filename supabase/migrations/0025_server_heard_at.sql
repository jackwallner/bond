-- A phone's clock can run a few minutes fast, and its completion keeps the date the
-- phone gave it. That date can fall just past midnight while the server is still in
-- the day before, and it must not count for the new day's reminder. So the server
-- also records when it heard, and a completion counts from the earlier of the two.
-- Offline completions keep their past date.
--
-- send-push asks whether any due row is left, since a claim that stops at its
-- examined limit returns few rows without having reached the end.

alter table public.reminder_events add column acted_seen_at timestamptz;

create or replace function public.reminder_events_clamp_acted_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.acted_at > now() + interval '5 minutes' then
        new.acted_at := now();
    end if;
    if tg_op = 'INSERT' then
        new.acted_seen_at := case when new.acted_at is not null then now() end;
    elsif new.acted_at is distinct from old.acted_at then
        new.acted_seen_at := case when new.acted_at is not null then now() end;
    else
        new.acted_seen_at := old.acted_seen_at;
    end if;
    return new;
end;
$$;

drop trigger reminder_events_clamp_acted_at on public.reminder_events;
create trigger reminder_events_clamp_acted_at
    before insert or update of acted_at, acted_seen_at on public.reminder_events
    for each row execute function public.reminder_events_clamp_acted_at();

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
          and (since is null or least(e.acted_at, e.acted_seen_at) >= since)
    );
end;
$$;

create function public.push_work_left()
returns boolean
language sql
stable
security definer set search_path = public
as $$
    select exists (
        select 1 from public.reminder_push_queue pq
          join public.reminders r on r.id = pq.reminder_id
          join public.push_devices d on d.user_id = r.target_id
         where pq.next_push_at <= now()
           and (pq.lease_until is null or pq.lease_until <= now())
    ) or exists (
        select 1 from public.push_signals ps
         where ps.due_at <= now()
           and (ps.lease_until is null or ps.lease_until <= now())
    );
$$;

revoke all on function public.push_work_left() from public, anon, authenticated;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.push_work_left() to service_role;
    end if;
end
$$;

notify pgrst, 'reload schema';
