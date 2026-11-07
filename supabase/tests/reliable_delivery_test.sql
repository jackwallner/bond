-- Reliable delivery (0019): leases and acknowledgements, the done check per
-- occurrence, completions and edits inside their couple, bad rows, registration,
-- phone signals and the daily random pick. Rolled back at the end.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email) values
    ('a0000000-0000-0000-0000-00000000000a', 'author@test'),
    ('b0000000-0000-0000-0000-00000000000b', 'target@test'),
    ('c0000000-0000-0000-0000-00000000000c', 'outsider@test');

insert into public.couples (id, partner_a, partner_b, solo) values
    ('d0000000-0000-0000-0000-00000000000d',
     'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b', false),
    ('dc000000-0000-0000-0000-00000000000c',
     'c0000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-00000000000c', true);

create function pg_temp.reminder(
    p_id text, p_trigger text, p_fire timestamptz, p_rrule text default null,
    p_hidden boolean default false
) returns uuid language sql as $$
    insert into public.reminders (id, couple_id, author_id, target_id, title, love_language,
                                  trigger_type, fire_at, rrule, surprise_hidden_from_partner)
    values (p_id::uuid, 'd0000000-0000-0000-0000-00000000000d',
            'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b',
            p_id, 'words', p_trigger, p_fire, p_rrule, p_hidden)
    returning id;
$$;

-- Puts a queue row due p_ago ago, and a one shot's time with it (with the
-- trigger off, because a past time would take it straight out of the queue).
create function pg_temp.due(p_id uuid, p_ago interval) returns void language plpgsql as $$
begin
    alter table public.reminders disable trigger reminders_sync_push_queue;
    update public.reminders set fire_at = now() - p_ago where id = p_id and trigger_type = 'one_time';
    alter table public.reminders enable trigger reminders_sync_push_queue;
    insert into public.reminder_push_queue (reminder_id, next_push_at) values (p_id, now() - p_ago)
        on conflict (reminder_id) do update set next_push_at = excluded.next_push_at;
    -- Dynamic so this file also runs, and fails, without 0019.
    if exists (select 1 from information_schema.columns
                where table_name = 'reminder_push_queue' and column_name = 'lease_until') then
        execute 'update public.reminder_push_queue set lease_until = null where reminder_id = $1' using p_id;
    end if;
end;
$$;

-- A fixed zone whose local time is 00:10 right now, as a POSIX zone (signs inverted).
create function pg_temp.zone_just_past_midnight() returns text language plpgsql as $$
declare
    minutes int := (10 - (extract(hour from now() at time zone 'UTC') * 60
                          + extract(minute from now() at time zone 'UTC'))::int + 1440) % 1440;
begin
    if minutes > 720 then minutes := minutes - 1440; end if;
    return format('XYZ%s%s:%s', case when minutes >= 0 then '-' else '+' end,
                  lpad((abs(minutes) / 60)::text, 2, '0'), lpad((abs(minutes) % 60)::text, 2, '0'));
end;
$$;

select set_config('test.uid', 'b0000000-0000-0000-0000-00000000000b', false);
select public.register_push_device(repeat('b', 64), 'production', 'UTC');

-- ============================================================
-- 1. Lease, then acknowledge
-- ============================================================
do $$
declare
    one uuid := pg_temp.reminder('e1000000-0000-0000-0000-000000000001', 'one_time', now() + interval '1 hour');
    day uuid := pg_temp.reminder('e1000000-0000-0000-0000-000000000002', 'recurring', now() - interval '1 day', 'FREQ=DAILY');
    late uuid := pg_temp.reminder('e1000000-0000-0000-0000-000000000003', 'one_time', now() + interval '1 hour');
    c record;
    due_one timestamptz;
    due_day timestamptz;
begin
    perform pg_temp.due(one, interval '1 minute');
    perform pg_temp.due(day, interval '1 minute');
    due_one := (select next_push_at from public.reminder_push_queue where reminder_id = one);
    due_day := (select next_push_at from public.reminder_push_queue where reminder_id = day);

    create temp table first_claim on commit drop as select * from public.claim_due_reminder_pushes();
    select * into c from first_claim where reminder_id = one;
    assert c.due_at = due_one, 'the claim says which occurrence it is';
    assert c.user_id = 'b0000000-0000-0000-0000-00000000000b', 'and whose';
    assert c.devices = jsonb_build_array(jsonb_build_object('token', repeat('b', 64), 'env', 'production')),
        'and where it goes: ' || c.devices;
    assert (select next_push_at from public.reminder_push_queue where reminder_id = one) = due_one,
        'a claim does not move a row on';
    assert (select count(*) from public.claim_due_reminder_pushes()) = 0, 'a leased row is not claimed twice';

    -- Not acknowledged (a crash, a 503): it comes back when the lease runs out.
    update public.reminder_push_queue set lease_until = now() - interval '1 second' where reminder_id in (one, day);
    assert (select count(*) from public.claim_due_reminder_pushes() x where x.reminder_id in (one, day)) = 2,
        'an unacknowledged occurrence is sent again';

    -- An acknowledgement for another occurrence changes nothing.
    perform public.ack_reminder_push(one, due_one - interval '1 day');
    assert exists (select 1 from public.reminder_push_queue where reminder_id = one), 'a stale ack is ignored';

    perform public.ack_reminder_push(one, due_one);
    perform public.ack_reminder_push(day, due_day);
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = one), 'an acked one shot leaves';
    assert (select next_push_at from public.reminder_push_queue where reminder_id = day) > now(),
        'an acked recurring row moves to its next time';
    assert (select lease_until from public.reminder_push_queue where reminder_id = day) is null, 'with no lease';

    -- Never acknowledged and now over an hour late: it moves on unsent.
    perform pg_temp.due(late, interval '61 minutes');
    assert (select count(*) from public.claim_due_reminder_pushes() x where x.reminder_id = late) = 0, 'too late';
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = late), 'and gone';
end
$$;

-- ============================================================
-- 2. Done is decided for the occurrence's own day
-- ============================================================
do $$
declare
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    late_night uuid := pg_temp.reminder('e2000000-0000-0000-0000-000000000001', 'recurring',
                                        now() - interval '3 days', 'FREQ=DAILY');
begin
    update public.push_devices set timezone = pg_temp.zone_just_past_midnight() where user_id = b;
    -- Due 20 minutes ago, which was yesterday on the phone, and done earlier yesterday.
    perform pg_temp.due(late_night, interval '20 minutes');
    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    values (late_night, 'd0000000-0000-0000-0000-00000000000d', now() - interval '2 hours');
    assert (select count(*) from public.claim_due_reminder_pushes() x where x.reminder_id = late_night) = 0,
        'yesterday''s occurrence was done yesterday';
    update public.push_devices set timezone = 'UTC' where user_id = b;
end
$$;

-- ============================================================
-- 3. Completions and edits stay inside their couple
-- ============================================================
grant usage on schema public to authenticated;
grant select, insert, update on public.reminder_events, public.reminders to authenticated;
grant select on public.couples to authenticated;

do $$
declare
    rid uuid := pg_temp.reminder('e3000000-0000-0000-0000-000000000001', 'recurring', now() - interval '1 day', 'FREQ=DAILY');
    hid uuid := pg_temp.reminder('e3000000-0000-0000-0000-000000000002', 'one_time', now() + interval '1 day', null, true);
    denied boolean;
begin
    -- An outsider writes a completion for it against their own couple.
    perform set_config('test.uid', 'c0000000-0000-0000-0000-00000000000c', false);
    set local role authenticated;
    denied := false;
    begin
        insert into public.reminder_events (reminder_id, couple_id, acted_at)
        values (rid, 'dc000000-0000-0000-0000-00000000000c', now() + interval '1 year');
    exception when insufficient_privilege then denied := true; end;
    assert denied, 'a completion for another couple''s reminder is refused';

    -- Nor can a reminder move into someone else's couple.
    insert into public.reminders (id, couple_id, author_id, target_id, title, love_language, trigger_type, fire_at)
    values ('e3000000-0000-0000-0000-0000000000c1', 'dc000000-0000-0000-0000-00000000000c',
            'c0000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-00000000000c',
            'Mine', 'words', 'one_time', now() + interval '1 day');
    denied := false;
    begin
        update public.reminders set couple_id = 'd0000000-0000-0000-0000-00000000000d'
         where id = 'e3000000-0000-0000-0000-0000000000c1';
    exception when insufficient_privilege then denied := true; end;
    assert denied, 'an author cannot move a reminder into another couple';

    -- The target marks a surprise done from its notification, though RLS hides it.
    perform set_config('test.uid', 'b0000000-0000-0000-0000-00000000000b', false);
    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    values (hid, 'd0000000-0000-0000-0000-00000000000d', now());
    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    values (rid, 'd0000000-0000-0000-0000-00000000000d', now() - interval '2 days');
    reset role;

    -- Even a row that got in some other way does not count.
    delete from public.reminder_events where reminder_id = rid;
    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    values (rid, 'dc000000-0000-0000-0000-00000000000c', now() + interval '1 year');
    assert not public.reminder_done_at((select r from public.reminders r where id = rid), 'UTC', now()),
        'a completion from another couple does not silence it';
end
$$;

-- ============================================================
-- 4. A row the schedule math cannot handle
-- ============================================================
do $$
declare
    good uuid := pg_temp.reminder('e4000000-0000-0000-0000-000000000001', 'one_time', now() + interval '1 hour');
    bad uuid := pg_temp.reminder('e4000000-0000-0000-0000-000000000002', 'recurring', now() + interval '1 hour', 'FREQ=DAILY');
    denied boolean := false;
    n int;
begin
    begin
        update public.reminders set fire_at = '-infinity' where id = bad;
    exception when check_violation then denied := true; end;
    assert denied, 'an infinite time is refused';
    denied := false;
    begin
        update public.reminders set window_start = 'infinity' where id = bad;
    exception when check_violation then denied := true; end;
    assert denied, 'an infinite window is refused';

    -- One written before the check (dropped here to make it).
    alter table public.reminders drop constraint reminders_times_finite;
    alter table public.reminders disable trigger reminders_sync_push_queue;
    update public.reminders set fire_at = '-infinity' where id = bad;
    alter table public.reminders enable trigger reminders_sync_push_queue;

    -- Registering survives it.
    perform set_config('test.uid', 'b0000000-0000-0000-0000-00000000000b', false);
    perform public.register_push_device(repeat('b', 64), 'production', 'UTC');

    -- The claim gets past it when it is too late to send and has to move on.
    perform pg_temp.due(bad, interval '2 hours');
    perform pg_temp.due(good, interval '1 minute');
    create temp table bad_claim on commit drop as select * from public.claim_due_reminder_pushes();
    assert exists (select 1 from bad_claim where reminder_id = good), 'the good row is still sent';
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = bad), 'the bad row leaves the queue';

    -- And the acknowledgement gets past it when it was sent.
    perform pg_temp.due(bad, interval '2 minutes');
    select count(*) into n from public.claim_due_reminder_pushes() x where x.reminder_id = bad;
    assert n = 1, 'sent';
    perform public.ack_reminder_push(bad, now() - interval '2 minutes');
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = bad), 'then leaves the queue';

    -- A save of it and a pairing change still go through.
    update public.reminders set title = 'Renamed', rrule = 'FREQ=WEEKLY' where id = bad;
    assert (select title from public.reminders where id = bad) = 'Renamed', 'the save is kept';
    update public.couples set solo = true, partner_b = partner_a where id = 'd0000000-0000-0000-0000-00000000000d';
    update public.couples set solo = false, partner_b = 'b0000000-0000-0000-0000-00000000000b'
     where id = 'd0000000-0000-0000-0000-00000000000d';
    assert (select not solo from public.couples where id = 'd0000000-0000-0000-0000-00000000000d'), 'paired again';
    alter table public.reminders add constraint reminders_times_finite check (
        (fire_at is null or isfinite(fire_at)) and (window_start is null or isfinite(window_start))
        and (window_end is null or isfinite(window_end))) not valid;

    -- The daily pick cannot overflow: the largest hash is still a unit below 1.
    assert public.daily_pick_unit('ffffffff-ffff-ffff-ffff-ffffffffffff', 99999999) between 0 and 1, 'unit';
    delete from public.reminders where id = bad;
end
$$;

-- ============================================================
-- 5. Registration
-- ============================================================
do $$
declare
    a uuid := 'a0000000-0000-0000-0000-00000000000a';
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    kept uuid := pg_temp.reminder('e5000000-0000-0000-0000-000000000001', 'one_time', now() + interval '1 hour');
    first_due uuid;
    denied boolean;
    bad text;
begin
    -- Already served here: what is due and unsent stays due.
    perform pg_temp.due(kept, interval '30 seconds');
    perform set_config('test.uid', b::text, false);
    perform public.register_push_device(repeat('b', 64), 'production', 'UTC');
    assert exists (select 1 from public.reminder_push_queue where reminder_id = kept and next_push_at <= now()),
        'registering again keeps a due occurrence';

    -- A first phone rang it itself, so it is not sent again.
    insert into public.reminders (id, couple_id, author_id, target_id, title, love_language, trigger_type, fire_at)
    values ('e5000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-00000000000d', a, b,
            'x', 'words', 'one_time', now() + interval '1 hour');
    first_due := 'e5000000-0000-0000-0000-000000000002';
    delete from public.push_devices where user_id = b;
    perform pg_temp.due(first_due, interval '30 seconds');
    perform public.register_push_device(repeat('b', 64), 'production', 'UTC');
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = first_due),
        'a first phone does not get what already rang on it';

    foreach bad in array array['token-1', repeat('g', 64), repeat('a', 63), repeat('a', 201), ''] loop
        denied := false;
        begin
            perform public.register_push_device(bad, 'production', 'UTC');
        exception when invalid_parameter_value then denied := true; end;
        assert denied, 'not an APNs token: ' || bad;
    end loop;
    perform public.register_push_device(upper(repeat('ab', 32)), 'production', 'UTC');

    -- Five phones at most, the newest kept.
    for i in 1..7 loop
        perform public.register_push_device(repeat(to_hex(i), 64), 'production', 'UTC');
        update public.push_devices set updated_at = now() - (10 - i) * interval '1 minute'
         where token = repeat(to_hex(i), 64);
    end loop;
    assert (select count(*) from public.push_devices where user_id = b) <= 5, 'five phones at most';
    assert exists (select 1 from public.push_devices where token = repeat('7', 64)), 'the newest stays';

    -- A zone the server does not know keeps the one it had.
    perform public.register_push_device(repeat('7', 64), 'production', 'America/Chicago', 1);
    perform public.register_push_device(repeat('7', 64), 'production', 'Not/AZone');
    assert (select timezone from public.push_devices where token = repeat('7', 64)) = 'America/Chicago',
        'an unknown zone keeps the known one';

    -- A token that moves accounts does not keep the old account's week.
    perform set_config('test.uid', a::text, false);
    perform public.register_push_device(repeat('7', 64), 'production', 'UTC');
    assert (select first_weekday from public.push_devices where token = repeat('7', 64)) is null,
        'the week start stays with the old account';

    -- A dead token goes only while it is still the same account's.
    perform public.delete_push_device(repeat('7', 64), b);
    assert exists (select 1 from public.push_devices where token = repeat('7', 64)), 'moved on, not deleted';
    perform public.delete_push_device(repeat('7', 64), a);
    assert not exists (select 1 from public.push_devices where token = repeat('7', 64)), 'deleted';
    perform set_config('test.uid', b::text, false);
    delete from public.push_devices where user_id = b and token <> repeat('b', 64);
end
$$;

-- ============================================================
-- 6. Phones are told when what they armed changed
-- ============================================================
do $$
declare
    a uuid := 'a0000000-0000-0000-0000-00000000000a';
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    d uuid := 'd0000000-0000-0000-0000-00000000000d';
    loc uuid := pg_temp.reminder('e6000000-0000-0000-0000-000000000001', 'location', null);
    gone uuid := pg_temp.reminder('e6000000-0000-0000-0000-000000000002', 'location', null);
    c record;
begin
    perform set_config('test.uid', a::text, false);
    perform public.register_push_device(repeat('a', 64), 'production', 'UTC');
    delete from public.push_signals;
    delete from public.reminder_push_queue;

    -- A place the partner removes is disarmed.
    delete from public.reminders where id = gone;
    assert exists (select 1 from public.push_signals where user_id = b), 'deleting a place tells the phone';
    delete from public.push_signals;
    update public.reminders set trigger_type = 'one_time', fire_at = now() + interval '1 day' where id = loc;
    assert exists (select 1 from public.push_signals where user_id = b), 'so does turning it into a time';
    update public.reminders set trigger_type = 'location', fire_at = null where id = loc;
    delete from public.push_signals;
    delete from public.reminder_push_queue;

    -- Unpairing tells both phones.
    perform set_config('test.uid', b::text, false);
    perform public.leave_couple(b);
    assert (select count(*) from public.push_signals where user_id in (a, b)) = 2, 'both phones hear of the unpair';

    create temp table signal_claim on commit drop as select * from public.claim_due_reminder_pushes();
    select * into c from signal_claim where user_id = b;
    assert c.reminder_id is null and c.silent and c.title is null and c.body is null, 'a silent push with nothing in it';
    assert jsonb_array_length(c.devices) = 1, 'to each of the user''s phones';
    assert (select count(*) from public.claim_due_reminder_pushes()) = 0, 'leased like the rest';
    perform public.ack_reminder_push(null, s.due_at, s.user_id) from signal_claim s;
    assert not exists (select 1 from public.push_signals), 'acknowledged, gone';

    -- Pairing again tells them too, and the place is armed again.
    delete from public.couples where partner_a = b and partner_b = b;
    update public.couples set partner_b = b, solo = false where id = d;
    assert (select count(*) from public.push_signals where user_id in (a, b)) = 2, 'both phones hear of the pairing';
    assert (select silent from public.reminder_push_queue where reminder_id = loc), 'the place gets its silent push';

    -- A newer signal outlives the acknowledgement of an older one.
    perform public.ack_reminder_push(null, now() - interval '1 minute', b);
    assert exists (select 1 from public.push_signals where user_id = b), 'a newer signal stays';
end
$$;

-- ============================================================
-- 7. Daily random: the phone's moment, today when made inside the window
-- ============================================================
do $$
declare
    r public.reminders;
    t timestamptz;
    tz text := 'America/Los_Angeles';
begin
    r.id := 'e7000000-0000-0000-0000-000000000001';
    r.author_id := 'a0000000-0000-0000-0000-00000000000a';
    r.target_id := 'b0000000-0000-0000-0000-00000000000b';
    r.trigger_type := 'random_window';
    r.rrule := 'FREQ=DAILY';
    r.window_start := '2030-01-01 18:00 America/Los_Angeles';
    r.window_end := '2030-01-01 21:00 America/Los_Angeles';
    r.created_at := '2029-01-01 00:00+00';

    -- The same moment NotificationScheduler.stablePick gives (BondTests,
    -- DailyRandomAgreementTests): FNV-1a of the id and the day's ordinal.
    t := public.reminder_next_push_at(r, '2030-05-06 12:00 America/Los_Angeles', tz);
    assert t = '2030-05-07 03:35:33.5544+00'::timestamptz, 'the phone''s pick: ' || t;

    -- Made at 20:40, after that moment: it still comes before 21:00 today.
    r.created_at := '2030-05-06 20:40 America/Los_Angeles';
    t := public.reminder_next_push_at(r, r.created_at, tz);
    assert t = '2030-05-07 03:57:25.20852+00'::timestamptz, 'made inside the window, today: ' || t;

    -- Saved in summer, the window keeps its wall clock in winter.
    r.created_at := '2029-01-01 00:00+00';
    r.window_start := '2030-07-01 23:30 America/Los_Angeles';
    r.window_end := '2030-07-01 23:45 America/Los_Angeles';
    t := public.reminder_next_push_at(r, '2030-12-01 12:00 America/Los_Angeles', tz);
    assert (t at time zone tz)::date = '2030-12-01'
       and (t at time zone tz)::time between '23:30' and '23:45', 'winter keeps the window: ' || t;

    -- The days the clocks change still get one.
    r.window_start := '2030-07-01 02:00 America/Los_Angeles';
    r.window_end := '2030-07-01 02:59 America/Los_Angeles';
    t := public.reminder_next_push_at(r, '2030-03-10 00:00 America/Los_Angeles', tz);
    assert (t at time zone tz)::date = '2030-03-10', 'spring forward keeps its day: ' || t;
    r.window_start := '2030-07-01 01:00 America/Los_Angeles';
    r.window_end := '2030-07-01 01:30 America/Los_Angeles';
    t := public.reminder_next_push_at(r, '2030-11-03 00:00 America/Los_Angeles', tz);
    assert (t at time zone tz)::date = '2030-11-03', 'fall back keeps its day: ' || t;
end
$$;

-- ============================================================
-- 9. Unpairing and pairing keep every completion in its reminder's couple
-- ============================================================
do $$
declare
    a uuid := 'a0000000-0000-0000-0000-00000000000a';
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    c uuid := 'c0000000-0000-0000-0000-00000000000c';
    d uuid := 'd0000000-0000-0000-0000-00000000000d';
    mismatched int;
begin
    -- Back to a paired a and b, each with a reminder for the other and a completion on each.
    delete from public.couples where id <> d and (partner_a in (a, b) or partner_b in (a, b));
    update public.couples set partner_a = a, partner_b = b, solo = false where id = d;
    insert into public.reminders (id, couple_id, author_id, target_id, title, love_language, trigger_type, fire_at)
    values ('e9000000-0000-0000-0000-000000000001', d, a, b, 'from a', 'words', 'one_time', now() + interval '1 day'),
           ('e9000000-0000-0000-0000-000000000002', d, b, a, 'from b', 'words', 'one_time', now() + interval '1 day');
    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    select id, d, now() from public.reminders where id in ('e9000000-0000-0000-0000-000000000001',
                                                          'e9000000-0000-0000-0000-000000000002');

    perform set_config('test.uid', b::text, false);
    perform public.leave_couple(b);
    select count(*) into mismatched from public.reminder_events e join public.reminders r on r.id = e.reminder_id
     where e.couple_id <> r.couple_id and r.id::text like 'e9%';
    assert mismatched = 0, 'leave_couple moved a completion away from its reminder';

    -- b invites from their solo couple, a joins from theirs: the two merge.
    insert into public.invite_codes (code, created_by, expires_at) values ('MERGE9', b, now() + interval '1 hour');
    perform set_config('test.uid', a::text, false);
    perform public.consume_invite_code('MERGE9', a);
    select count(*) into mismatched from public.reminder_events e join public.reminders r on r.id = e.reminder_id
     where e.couple_id <> r.couple_id and r.id::text like 'e9%';
    assert mismatched = 0, 'consume_invite_code moved a completion away from its reminder';
    assert (select count(*) from public.reminder_events e
             where e.reminder_id in ('e9000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000002')) = 2,
        'and none was lost';
end
$$;

-- ============================================================
-- 8. Privileges
-- ============================================================
do $$
declare
    fn text;
begin
    foreach fn in array array[
        'public.claim_due_reminder_pushes(int)', 'public.ack_reminder_push(uuid, timestamptz, uuid)',
        'public.delete_push_device(text, uuid)', 'public.get_apns_provider_token(text)',
        'public.put_apns_provider_token(text, text, timestamptz)'
    ] loop
        assert not has_function_privilege('anon', fn, 'execute'), fn || ' is closed to anon';
        assert not has_function_privilege('authenticated', fn, 'execute'), fn || ' is closed to signed in users';
        assert has_function_privilege('service_role', fn, 'execute'), fn || ' is open to the service role';
    end loop;
    foreach fn in array array[
        'public.signal_push_user(uuid)', 'public.daily_pick_unit(uuid, bigint)',
        'public.daily_window(public.reminders, date, text)', 'public.reminder_armed_on_phone(public.reminders)',
        'public.sync_reminder_push(public.reminders)', 'public.reminders_signal_on_delete()',
        'public.finish_reminder_push(public.reminder_push_queue, public.reminders)',
        'public.refresh_reminder_push(public.reminders)', 'public.reminder_next_push_at(public.reminders, timestamptz, text)',
        'public.reminder_done_at(public.reminders, text, timestamptz)', 'public.couples_sync_push_queue()',
        'public.reminders_sync_push_queue()'
    ] loop
        assert not has_function_privilege('anon', fn, 'execute'), fn || ' is closed to anon';
        assert not has_function_privilege('authenticated', fn, 'execute'), fn || ' is closed to signed in users';
    end loop;
    foreach fn in array array['public.reminder_in_couple(uuid, uuid)', 'public.register_push_device(text, text, text)'] loop
        assert not has_function_privilege('anon', fn, 'execute'), fn || ' is closed to anon';
        assert has_function_privilege('authenticated', fn, 'execute'), fn || ' is open to signed in users';
    end loop;
    foreach fn in array array['public.push_signals', 'public.apns_provider_tokens'] loop
        assert not has_table_privilege('anon', fn, 'select'), fn || ' is closed to anon';
        assert not has_table_privilege('authenticated', fn, 'select'), fn || ' is closed to signed in users';
    end loop;
end
$$;

rollback;

\echo 'reliable delivery tests passed'
