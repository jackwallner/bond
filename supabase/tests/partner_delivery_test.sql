-- Partner delivery (0014): the target can move and remove a partner's reminder
-- and nothing else about it, and the server delivers it when it is due. Plain
-- plpgsql assertions, rolled back at the end, like rpc_lifecycle_test.sql.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email) values
    ('a0000000-0000-0000-0000-00000000000a', 'author@test'),
    ('b0000000-0000-0000-0000-00000000000b', 'target@test'),
    ('c0000000-0000-0000-0000-00000000000c', 'outsider@test');

insert into public.couples (id, partner_a, partner_b, solo) values
    ('d0000000-0000-0000-0000-00000000000d',
     'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b', false);

create function pg_temp.reminder(
    p_id text, p_trigger text, p_fire timestamptz, p_rrule text default null,
    p_hidden boolean default false, p_ws timestamptz default null, p_we timestamptz default null
) returns uuid language sql as $$
    insert into public.reminders (id, couple_id, author_id, target_id, title, love_language,
                                  trigger_type, fire_at, rrule, window_start, window_end,
                                  surprise_hidden_from_partner)
    values (p_id::uuid, 'd0000000-0000-0000-0000-00000000000d',
            'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b',
            p_id, 'words', p_trigger, p_fire, p_rrule, p_ws, p_we, p_hidden)
    returning id;
$$;

-- Moves a one shot's time and its queue row into the past, with the trigger off
-- because a past time would take it straight out of the queue.
create function pg_temp.make_due(p_ids uuid[], p_ago interval) returns void language plpgsql as $$
begin
    alter table public.reminders disable trigger reminders_sync_push_queue;
    update public.reminders set fire_at = now() - p_ago
     where id = any(p_ids) and trigger_type = 'one_time';
    alter table public.reminders enable trigger reminders_sync_push_queue;
    update public.reminder_push_queue set next_push_at = now() - p_ago where reminder_id = any(p_ids);
end;
$$;

-- ============================================================
-- Scenario 1: reschedule_reminder and the target delete policy
-- ============================================================
do $$
declare
    a uuid := 'a0000000-0000-0000-0000-00000000000a';
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    c uuid := 'c0000000-0000-0000-0000-00000000000c';
    rid uuid := pg_temp.reminder('e1000000-0000-0000-0000-000000000001', 'one_time', now() + interval '1 day');
    hid uuid := pg_temp.reminder('e1000000-0000-0000-0000-000000000002', 'one_time', now() + interval '1 day', null, true);
    moved timestamptz := now() + interval '3 days';
    denied boolean;
    row_after public.reminders;
begin
    perform set_config('test.uid', b::text, false);
    perform public.reschedule_reminder(rid, 'one_time', moved, null, null, null, null);
    select * into row_after from public.reminders where id = rid;
    assert row_after.fire_at = moved, 'the target can move a partner reminder';
    assert row_after.title = rid::text and row_after.author_id = a, 'nothing else about it changes';

    denied := false;
    begin
        perform public.reschedule_reminder(hid, 'one_time', moved, null, null, null, null);
    exception when others then denied := true; end;
    assert denied, 'a hidden surprise cannot be moved by its target';

    perform set_config('test.uid', c::text, false);
    denied := false;
    begin
        perform public.reschedule_reminder(rid, 'one_time', moved, null, null, null, null);
    exception when others then denied := true; end;
    assert denied, 'an outsider cannot move it';
end
$$;

-- RLS needs a role that does not bypass it.
grant usage on schema public to authenticated;
grant select, delete on public.reminders to authenticated;
grant select on public.couples to authenticated;

set role authenticated;
select set_config('test.uid', 'c0000000-0000-0000-0000-00000000000c', false);
delete from public.reminders where id = 'e1000000-0000-0000-0000-000000000001';
select set_config('test.uid', 'b0000000-0000-0000-0000-00000000000b', false);
delete from public.reminders where id = 'e1000000-0000-0000-0000-000000000002';
reset role;
do $$
begin
    assert exists (select 1 from public.reminders where id = 'e1000000-0000-0000-0000-000000000001'),
        'an outsider cannot delete it';
    assert exists (select 1 from public.reminders where id = 'e1000000-0000-0000-0000-000000000002'),
        'the target cannot delete a hidden surprise';
end
$$;
set role authenticated;
delete from public.reminders where id = 'e1000000-0000-0000-0000-000000000001';
reset role;
do $$
begin
    assert not exists (select 1 from public.reminders where id = 'e1000000-0000-0000-0000-000000000001'),
        'the target can delete a partner reminder';
end
$$;

-- ============================================================
-- Scenario 2: next delivery times
-- ============================================================
do $$
declare
    r public.reminders;
    t timestamptz;
begin
    r.id := gen_random_uuid();
    r.author_id := 'a0000000-0000-0000-0000-00000000000a';
    r.target_id := 'b0000000-0000-0000-0000-00000000000b';

    r.trigger_type := 'one_time';
    r.fire_at := '2030-01-10 12:00+00';
    assert public.reminder_next_push_at(r, '2030-01-01 00:00+00', 'UTC') = r.fire_at, 'one time, ahead';
    assert public.reminder_next_push_at(r, '2030-01-11 00:00+00', 'UTC') is null, 'one time, past';

    r.trigger_type := 'recurring';
    r.rrule := 'FREQ=DAILY';
    r.fire_at := '2030-03-01 08:00 America/Los_Angeles';
    t := public.reminder_next_push_at(r, '2030-03-20 09:00 America/Los_Angeles', 'America/Los_Angeles');
    assert t = '2030-03-21 08:00 America/Los_Angeles'::timestamptz, 'daily holds 8 AM across daylight saving: ' || t;

    r.rrule := 'FREQ=WEEKLY';
    r.fire_at := '2030-01-07 09:00+00';
    t := public.reminder_next_push_at(r, '2030-01-14 09:00+00', 'UTC');
    assert t = '2030-01-21 09:00+00'::timestamptz, 'weekly, exactly on one moves to the next: ' || t;

    r.rrule := 'FREQ=MONTHLY';
    r.fire_at := '2030-01-31 09:00+00';
    t := public.reminder_next_push_at(r, '2030-02-01 00:00+00', 'UTC');
    assert t = '2030-02-28 09:00+00'::timestamptz, 'monthly on the 31st clamps: ' || t;
    t := public.reminder_next_push_at(r, '2030-03-01 00:00+00', 'UTC');
    assert t = '2030-03-31 09:00+00'::timestamptz, 'and comes back without drifting: ' || t;

    r.rrule := 'FREQ=YEARLY';
    r.fire_at := '2028-06-01 09:00+00';
    t := public.reminder_next_push_at(r, '2030-07-01 00:00+00', 'UTC');
    assert t = '2031-06-01 09:00+00'::timestamptz, 'yearly: ' || t;

    r.trigger_type := 'random_window';
    r.rrule := 'FREQ=DAILY';
    r.window_start := '2030-01-01 18:00+00';
    r.window_end := '2030-01-01 21:00+00';
    t := public.reminder_next_push_at(r, '2030-05-05 22:00+00', 'UTC');
    assert t >= '2030-05-06 18:00+00'::timestamptz and t <= '2030-05-06 21:00+00'::timestamptz,
        'daily random window falls inside tomorrow''s window: ' || t;
    assert t = public.reminder_next_push_at(r, '2030-05-05 22:00+00', 'UTC'), 'and the pick is stable';

    r.trigger_type := 'location';
    assert public.reminder_next_push_at(r, now(), 'UTC') is null, 'location has no time';

    r.trigger_type := 'one_time';
    r.rrule := null;
    r.fire_at := '2030-01-10 12:00+00';
    r.target_id := r.author_id;
    assert public.reminder_next_push_at(r, '2030-01-01 00:00+00', 'UTC') is null, 'self reminders stay local';
end
$$;

-- ============================================================
-- Scenario 3: the queue and delivery
-- ============================================================
do $$
declare
    a uuid := 'a0000000-0000-0000-0000-00000000000a';
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    one uuid := pg_temp.reminder('e2000000-0000-0000-0000-000000000001', 'one_time', now() + interval '1 hour');
    hid uuid := pg_temp.reminder('e2000000-0000-0000-0000-000000000002', 'one_time', now() + interval '1 hour', null, true);
    day uuid := pg_temp.reminder('e2000000-0000-0000-0000-000000000003', 'recurring', now() - interval '1 hour', 'FREQ=DAILY');
    done uuid := pg_temp.reminder('e2000000-0000-0000-0000-000000000004', 'one_time', now() + interval '1 hour');
    old uuid := pg_temp.reminder('e2000000-0000-0000-0000-000000000005', 'one_time', now() + interval '1 hour');
    n int;
    next_at timestamptz;
begin
    assert (select count(*) from public.reminder_push_queue where reminder_id in (one, hid, day, done, old)) = 5,
        'every partner reminder is queued, a hidden surprise too';

    update public.reminders set title = 'Renamed' where id = one;
    assert (select next_push_at from public.reminder_push_queue where reminder_id = one) > now(),
        'a rename leaves the time alone';

    -- Nothing is due, and with no device nothing is ever claimed.
    perform pg_temp.make_due(array[one, hid, day, done], interval '1 minute');
    perform pg_temp.make_due(array[old], interval '2 hours');
    assert (select count(*) from public.claim_due_reminder_pushes()) = 0, 'no device, nothing claimed';

    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    values (done, 'd0000000-0000-0000-0000-00000000000d', now());

    -- Registering re-reads the schedule, so what went by unsent is not delivered late.
    perform set_config('test.uid', b::text, false);
    perform public.register_push_device(repeat('1', 64), 'production', 'Not/AZone');
    assert (select timezone from public.push_devices where token = repeat('1', 64)) = 'UTC', 'bad zones fall back to UTC';
    perform public.register_push_device(repeat('1', 64), 'production', 'America/New_York');
    perform public.register_push_device(repeat('2', 64), 'sandbox', 'America/New_York');

    assert not exists (select 1 from public.reminder_push_queue where reminder_id = one),
        'a one shot that went by unsent is not delivered late';
    update public.reminders set fire_at = now() + interval '1 hour' where id in (one, hid, done, old);
    assert (select count(*) from public.reminder_push_queue where reminder_id = one) = 1, 'moved ahead, queued again';
    perform pg_temp.make_due(array[one, hid, day, done], interval '1 minute');
    perform pg_temp.make_due(array[old], interval '2 hours');

    create temp table claimed on commit drop as select * from public.claim_due_reminder_pushes();

    assert (select jsonb_array_length(devices) from claimed where reminder_id = one) = 2, 'one push per device';
    assert (select jsonb_array_length(devices) from claimed where reminder_id = hid) = 2, 'a hidden surprise is delivered';
    assert (select jsonb_array_length(devices) from claimed where reminder_id = day) = 2, 'a recurring occurrence is delivered';
    assert (select count(*) from claimed where reminder_id = done) = 0, 'marked done, not delivered';
    assert (select count(*) from claimed where reminder_id = old) = 0, 'two hours late, not delivered';
    assert (select count(*) from public.claim_due_reminder_pushes()) = 0, 'a claimed row is leased';

    -- Sent: send-push acknowledges each occurrence.
    perform public.ack_reminder_push(c.reminder_id, c.due_at) from claimed c;

    next_at := (select next_push_at from public.reminder_push_queue where reminder_id = day);
    assert next_at > now() and next_at <= now() + interval '1 day', 'a recurring row moves to its next time';
    assert not exists (select 1 from public.reminder_push_queue where reminder_id in (one, hid)),
        'a one shot leaves the queue';
    assert (select count(*) from public.claim_due_reminder_pushes()) = 0, 'a second claim finds nothing';

    -- Done for today is not done for good.
    update public.reminder_push_queue set next_push_at = now() - interval '1 minute' where reminder_id = day;
    insert into public.reminder_events (reminder_id, couple_id, acted_at)
    values (day, 'd0000000-0000-0000-0000-00000000000d', now());
    assert (select count(*) from public.claim_due_reminder_pushes()) = 0, 'done today, skipped today';
    assert exists (select 1 from public.reminder_push_queue where reminder_id = day), 'but it stays queued';

    -- The token is the phone: another account signing in takes it over.
    perform set_config('test.uid', a::text, false);
    perform public.unregister_push_device(repeat('1', 64));
    assert exists (select 1 from public.push_devices where token = repeat('1', 64)), 'not your device, not removed';
    perform public.register_push_device(repeat('1', 64), 'production', 'UTC');
    assert (select user_id from public.push_devices where token = repeat('1', 64)) = a, 'the token moves accounts';
    perform public.unregister_push_device(repeat('1', 64));
    assert not exists (select 1 from public.push_devices where token = repeat('1', 64)), 'sign out removes it';
    perform public.delete_push_device(repeat('2', 64));
    assert not exists (select 1 from public.push_devices where token = repeat('2', 64)), 'a dead token is removed';
end
$$;

-- ============================================================
-- Scenario 4: a location reminder gets one silent push, and a hidden one none
-- ============================================================
do $$
declare
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    loc uuid := pg_temp.reminder('e3000000-0000-0000-0000-000000000001', 'location', null);
    hid uuid := pg_temp.reminder('e3000000-0000-0000-0000-000000000002', 'location', null, null, true);
    n int;
begin
    perform set_config('test.uid', b::text, false);
    perform public.register_push_device(repeat('3', 64), 'production', 'UTC');

    assert (select silent from public.reminder_push_queue where reminder_id = loc), 'queued silent';
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = hid), 'no way to arm a hidden one';

    create temp table claimed_loc on commit drop as select * from public.claim_due_reminder_pushes();
    select count(*) into n from claimed_loc c where c.reminder_id = loc and c.silent;
    assert n = 1, 'one silent push';
    perform public.ack_reminder_push(c.reminder_id, c.due_at) from claimed_loc c where c.reminder_id is not null;
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = loc), 'and it is gone';
end
$$;

-- ============================================================
-- Scenario 5: the existing write paths still work with the trigger in place
-- ============================================================
do $$
declare
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    r uuid := pg_temp.reminder('e4000000-0000-0000-0000-000000000001', 'one_time', now() + interval '1 hour');
begin
    update public.reminders set target_id = author_id where id = r;
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = r),
        'retargeted to the author, out of the queue';
    update public.reminders set target_id = b where id = r;
    assert exists (select 1 from public.reminder_push_queue where reminder_id = r), 'and back in';
    delete from public.reminders where id = r;
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = r), 'delete cascades';
end
$$;

-- ============================================================
-- Scenario 6: Unpair cuts delivery in both directions, and pairing again restores it
-- ============================================================
do $$
declare
    a uuid := 'a0000000-0000-0000-0000-00000000000a';
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    d uuid := 'd0000000-0000-0000-0000-00000000000d';
    to_b uuid := pg_temp.reminder('e5000000-0000-0000-0000-000000000001', 'recurring', now() - interval '1 hour', 'FREQ=DAILY');
    to_a uuid := 'e5000000-0000-0000-0000-000000000002';
    loc uuid := pg_temp.reminder('e5000000-0000-0000-0000-000000000003', 'location', null);
    n int;
begin
    insert into public.reminders (id, couple_id, author_id, target_id, title, love_language,
                                  trigger_type, fire_at, rrule)
    values (to_a, d, b, a, to_a::text, 'words', 'recurring', now() - interval '1 hour', 'FREQ=DAILY');

    perform set_config('test.uid', a::text, false);
    perform public.register_push_device(repeat('a', 64), 'production', 'UTC');
    perform set_config('test.uid', b::text, false);
    perform public.register_push_device(repeat('b', 64), 'production', 'UTC');
    assert (select count(*) from public.reminder_push_queue where reminder_id in (to_b, to_a, loc)) = 3,
        'paired, all three are queued';

    perform public.leave_couple(b);
    assert not exists (select 1 from public.reminder_push_queue where reminder_id in (to_b, to_a, loc)),
        'unpairing empties the queue in both directions';

    -- The ex can still edit their own row, and an edit must not reach the other phone.
    update public.reminders set title = 'Still here', fire_at = now() + interval '1 hour' where id = to_b;
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = to_b), 'an edit does not requeue';
    update public.reminders set trigger_type = 'location', fire_at = null, rrule = null where id = to_b;
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = to_b), 'nor does a location edit';
    update public.reminders set trigger_type = 'recurring', fire_at = now() - interval '1 hour', rrule = 'FREQ=DAILY' where id = to_b;

    -- A row that got into the queue before the split is dropped, not sent.
    insert into public.reminder_push_queue (reminder_id, next_push_at, silent) values (to_b, now(), false);
    select count(*) into n from public.claim_due_reminder_pushes() c where c.reminder_id = to_b;
    assert n = 0, 'a queued row for an ex is not delivered';
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = to_b), 'and it leaves the queue';

    -- Someone new does not inherit the ex's reminders either.
    update public.couples set partner_b = 'c0000000-0000-0000-0000-00000000000c', solo = false where id = d;
    assert not exists (select 1 from public.reminder_push_queue where reminder_id = to_b), 'a new partner changes nothing';

    -- The same two pairing again get their reminders back.
    delete from public.couples where partner_a = b and partner_b = b;
    update public.couples set partner_b = b, solo = false where id = d;
    assert exists (select 1 from public.reminder_push_queue where reminder_id = to_b), 'paired again, queued again';
end
$$;

-- ============================================================
-- Scenario 7: only the service role can claim pushes or delete a device
-- ============================================================
do $$
declare
    fn text;
begin
    foreach fn in array array['public.claim_due_reminder_pushes(int)', 'public.delete_push_device(text)'] loop
        assert not has_function_privilege('anon', fn, 'execute'), fn || ' is closed to anon';
        assert not has_function_privilege('authenticated', fn, 'execute'), fn || ' is closed to signed in users';
        assert has_function_privilege('service_role', fn, 'execute'), fn || ' is open to the service role';
    end loop;
    foreach fn in array array['public.register_push_device(text, text, text)', 'public.unregister_push_device(text)',
                              'public.reschedule_reminder(uuid, text, timestamptz, text, jsonb, timestamptz, timestamptz)'] loop
        assert not has_function_privilege('anon', fn, 'execute'), fn || ' is closed to anon';
        assert has_function_privilege('authenticated', fn, 'execute'), fn || ' is open to signed in users';
    end loop;
end
$$;

-- ============================================================
-- Scenario 8: account RPCs need a signed in caller acting on themselves
-- ============================================================
do $$
declare
    b uuid := 'b0000000-0000-0000-0000-00000000000b';
    fn text;
    calls text[] := array[
        format('select public.delete_account(%L)', b),
        format('select public.leave_couple(%L)', b),
        format('select public.consume_invite_code(%L, %L)', 'CODE', b)
    ];
    call text;
    raised boolean;
begin
    foreach fn in array array['public.consume_invite_code(text, uuid)', 'public.create_solo_couple(text)',
                              'public.delete_account(uuid)', 'public.leave_couple(uuid)'] loop
        assert not has_function_privilege('anon', fn, 'execute'), fn || ' is closed to anon';
        assert has_function_privilege('authenticated', fn, 'execute'), fn || ' is open to signed in users';
    end loop;

    foreach call in array calls loop
        foreach fn in array array['', 'c0000000-0000-0000-0000-00000000000c'] loop
            perform set_config('test.uid', fn, false);
            raised := false;
            begin
                execute call;
            exception when others then
                raised := sqlerrm like '%unauthorized%';
            end;
            assert raised, call || ' refuses caller "' || fn || '"';
        end loop;
    end loop;
    assert exists (select 1 from auth.users where id = b), 'the account is still there';
end
$$;

rollback;

\echo 'partner delivery tests passed'
