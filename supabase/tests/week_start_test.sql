-- Device week start (0017, B15): a weekly partner reminder done on the phone's
-- Saturday is open again on its Sunday when the phone's week starts on Sunday,
-- as ReminderCompletion counts it on the device. Rolled back at the end.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email) values
    ('a0000000-0000-0000-0000-00000000000a', 'author@test'),
    ('b0000000-0000-0000-0000-00000000000b', 'target@test');

insert into public.couples (id, partner_a, partner_b, solo) values
    ('d0000000-0000-0000-0000-00000000000d',
     'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b', false);

insert into public.reminders (id, couple_id, author_id, target_id, title, love_language,
                              trigger_type, fire_at, rrule)
values ('e1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-00000000000d',
        'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b',
        'Date night', 'words', 'recurring', '2026-11-01 09:00 America/Los_Angeles', 'FREQ=WEEKLY'),
       ('e1000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-00000000000d',
        'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b',
        'Call', 'words', 'recurring', '2026-11-01 09:00 America/Los_Angeles', 'FREQ=DAILY');

-- Done on Saturday 2026-11-07 in Los Angeles.
insert into public.reminder_events (reminder_id, couple_id, fired_at, acted_at)
select id, 'd0000000-0000-0000-0000-00000000000d',
       '2026-11-07 10:00 America/Los_Angeles', '2026-11-07 10:00 America/Los_Angeles'
from public.reminders;

do $$
declare
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    weekly public.reminders;
    daily public.reminders;
    tz text := 'America/Los_Angeles';
    saturday timestamptz := '2026-11-07 18:00 America/Los_Angeles';
    sunday timestamptz := '2026-11-08 10:00 America/Los_Angeles';
    monday timestamptz := '2026-11-09 10:00 America/Los_Angeles';
begin
    select * into weekly from public.reminders where id = 'e1000000-0000-0000-0000-000000000001';
    select * into daily from public.reminders where id = 'e1000000-0000-0000-0000-000000000002';
    perform set_config('test.uid', b::text, false);

    -- A phone that never said keeps the Monday week it had.
    perform public.register_push_device('tok-b', 'sandbox', tz);
    assert public.reminder_done_at(weekly, tz, sunday), 'no first weekday: Sunday is still last week';
    assert not public.reminder_done_at(weekly, tz, monday), 'no first weekday: Monday starts a new week';

    -- A Sunday-first phone (en_US): Sunday starts a new week, as on the device.
    perform public.register_push_device('tok-b', 'sandbox', tz, 1);
    assert (select first_weekday from public.push_devices where token = 'tok-b') = 1, 'the first weekday is stored';
    assert public.reminder_done_at(weekly, tz, saturday), 'done on Saturday covers Saturday';
    assert not public.reminder_done_at(weekly, tz, sunday), 'Sunday is a new week on a Sunday-first phone';

    -- A Monday-first phone.
    perform public.register_push_device('tok-b', 'sandbox', tz, 2);
    assert public.reminder_done_at(weekly, tz, sunday), 'Sunday is the same week on a Monday-first phone';
    assert not public.reminder_done_at(weekly, tz, monday), 'Monday is a new week on a Monday-first phone';

    -- The store version re-registers without a weekday: the stored one stays.
    perform public.register_push_device('tok-b', 'sandbox', tz);
    assert (select first_weekday from public.push_devices where token = 'tok-b') = 2, 'an old registration keeps it';

    -- Nonsense is ignored, and the other periods are unchanged.
    perform public.register_push_device('tok-b', 'sandbox', tz, 9);
    assert (select first_weekday from public.push_devices where token = 'tok-b') is null, 'out of range is no answer';
    assert public.reminder_done_at(daily, tz, saturday), 'daily: done today';
    assert not public.reminder_done_at(daily, tz, sunday), 'daily: open the next day';
    assert public.reminder_done_now(daily, tz) = public.reminder_done_at(daily, tz, now()), 'done_now is done_at now';
end
$$;

do $$
begin
    assert not has_function_privilege('anon', 'public.register_push_device(text, text, text, int)', 'execute'),
        'the new registration is closed to anon';
    assert has_function_privilege('authenticated', 'public.register_push_device(text, text, text, int)', 'execute'),
        'and open to signed in users';
    assert has_function_privilege('authenticated', 'public.register_push_device(text, text, text)', 'execute'),
        'the store version still registers';
    assert not has_function_privilege('authenticated', 'public.push_first_weekday(uuid)', 'execute'),
        'push_first_weekday is internal';
    assert not has_function_privilege('anon', 'public.push_first_weekday(uuid)', 'execute'),
        'push_first_weekday is closed to anon';
    assert not has_function_privilege('authenticated', 'public.reminder_done_at(public.reminders, text, timestamptz)', 'execute'),
        'reminder_done_at is internal';
    assert not has_function_privilege('anon', 'public.reminder_done_at(public.reminders, text, timestamptz)', 'execute'),
        'reminder_done_at is closed to anon';
    assert not has_function_privilege('authenticated', 'public.reminder_done_now(public.reminders, text)', 'execute'),
        'reminder_done_now stays internal';
end
$$;

rollback;

\echo 'week start tests passed'
