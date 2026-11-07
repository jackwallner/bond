-- B15 (state machine audit 2026-11-06): a weekly partner reminder is "done for
-- this week" on the phone from the start of the phone's week, which follows the
-- region (Sunday in the US, Monday in most of Europe). reminder_done_now used
-- date_trunc('week'), always Monday, so a weekly reminder marked done on Saturday
-- in the US stayed done on the server through Sunday, and Sunday's push was
-- skipped while the app showed the reminder open.
--
-- The phone now sends its first weekday when it registers for push (a new
-- four-argument register_push_device; the three-argument one stays for the
-- versions in the store), and the server starts the week there. A device that
-- never sent one keeps the Monday week, which is what it had before.

alter table public.push_devices
    add column first_weekday smallint check (first_weekday between 1 and 7);

-- p_first_weekday counts like Calendar.firstWeekday: 1 is Sunday, 2 Monday.
create function public.register_push_device(
    p_token text, p_env text, p_timezone text, p_first_weekday int
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
    perform public.register_push_device(p_token, p_env, p_timezone);
    update public.push_devices
       set first_weekday = case when p_first_weekday between 1 and 7 then p_first_weekday end
     where token = p_token and user_id = auth.uid();
end;
$$;

-- The first weekday of the user's latest phone, Monday when none said.
create function public.push_first_weekday(p_user uuid)
returns int
language sql stable
set search_path = public
as $$
    select coalesce(
        (select first_weekday from public.push_devices
          where user_id = p_user order by updated_at desc limit 1),
        2
    );
$$;

-- Whether a completion covers the period containing p_now. Mirrors
-- ReminderCompletion.currentPeriodStart: a repeating reminder is done for its
-- current day, week, month or year in the target's zone (and, for a week, from
-- the target's first weekday), any other for good.
create function public.reminder_done_at(r public.reminders, p_tz text, p_now timestamptz)
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
            -- extract(dow) counts Sunday as 0; first weekday counts it as 1.
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
          and e.acted_at is not null
          and (since is null or e.acted_at >= since)
    );
end;
$$;

create or replace function public.reminder_done_now(r public.reminders, p_tz text)
returns boolean
language sql stable
set search_path = public
as $$
    select public.reminder_done_at(r, p_tz, now());
$$;

-- Supabase grants new public functions to anon, authenticated and service_role by
-- name. Only the app's own registration stays callable, and only when signed in.
revoke all on function public.register_push_device(text, text, text, int) from public, anon, authenticated;
grant execute on function public.register_push_device(text, text, text, int) to authenticated;
revoke all on function public.push_first_weekday(uuid) from public, anon, authenticated;
revoke all on function public.reminder_done_at(public.reminders, text, timestamptz) from public, anon, authenticated;
revoke all on function public.reminder_done_now(public.reminders, text) from public, anon, authenticated;
