-- RPC lifecycle tests: pairing, unpairing, and account deletion must never
-- destroy a partner's data. Plain plpgsql assertions (no pgTAP) so they run on
-- any Postgres via scripts/test-db.sh. Each scenario is a self-contained DO
-- block using its own UUIDs; the whole run is rolled back at the end.
--
-- Acting user is selected with set_config('test.uid', <uuid>, false), which the
-- stubbed auth.uid() reads — mirroring how Supabase derives auth.uid() from the
-- caller's JWT.

\set ON_ERROR_STOP on

begin;

-- ============================================================
-- Scenario 1 — consume_invite_code: pair-in-place MERGE keeps both sides' data
-- ============================================================
do $$
declare
    a uuid := '11111111-1111-1111-1111-111111111111';
    b uuid := '22222222-2222-2222-2222-222222222222';
    ca uuid; cb uuid; paired uuid;
    n int;
begin
    insert into auth.users (id, email) values (a, 'a1@test'), (b, 'b1@test');

    -- Each starts in their own solo couple with one reminder + one milestone.
    insert into public.couples (partner_a, partner_b, solo) values (a, a, true) returning id into ca;
    insert into public.couples (partner_a, partner_b, solo) values (b, b, true) returning id into cb;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (ca, a, a, 'A solo reminder', 'words', 'one_time'),
               (cb, b, b, 'B solo reminder', 'words', 'one_time');
    insert into public.milestones (couple_id, kind, date) values (ca, 'anniv', '2025-01-01'), (cb, 'bday', '2025-02-02');

    -- A invites; B consumes.
    insert into public.invite_codes (code, created_by, expires_at) values ('CODE1', a, now() + interval '1 day');
    perform set_config('test.uid', b::text, false);
    select public.consume_invite_code('CODE1', b) into paired;

    -- Exactly one couple now spans A and B, and it is a real (non-solo) couple.
    select count(*) into n from public.couples where partner_a in (a, b) or partner_b in (a, b);
    if n <> 1 then raise exception 'S1: expected 1 couple after merge, got %', n; end if;

    if not exists (
        select 1 from public.couples
        where id = paired and solo = false
          and partner_a = a and partner_b = b
    ) then raise exception 'S1: merged couple is not the expected real (a,b) couple'; end if;

    -- Both reminders and both milestones survived and live under the merged couple.
    select count(*) into n from public.reminders where couple_id = paired;
    if n <> 2 then raise exception 'S1: expected 2 reminders on merged couple, got %', n; end if;
    select count(*) into n from public.milestones where couple_id = paired;
    if n <> 2 then raise exception 'S1: expected 2 milestones on merged couple, got %', n; end if;

    -- The stale solo couple is gone.
    if exists (select 1 from public.couples where id = cb) then
        raise exception 'S1: stale solo couple was not removed';
    end if;

    raise notice 'S1 consume_invite_code merge: PASS';
end $$;

-- ============================================================
-- Scenario 2 — leave_couple: UNPAIR splits into two solos, each keeps own data
-- ============================================================
do $$
declare
    a uuid := '33333333-3333-3333-3333-333333333333';  -- partner_a (keeper)
    b uuid := '44444444-4444-4444-4444-444444444444';  -- partner_b (mover)
    c uuid; d uuid;
    r_a uuid; r_b uuid;
    q  uuid;
    n int;
begin
    insert into auth.users (id, email) values (a, 'a2@test'), (b, 'b2@test');
    insert into public.couples (partner_a, partner_b, solo) values (a, b, false) returning id into c;

    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, a, b, 'A reminder', 'words', 'one_time') returning id into r_a;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, b, a, 'B reminder', 'acts', 'one_time') returning id into r_b;
    insert into public.reminder_events (reminder_id, couple_id) values (r_a, c), (r_b, c);
    insert into public.milestones (couple_id, kind, date) values (c, 'anniv', '2024-06-01');

    select id into q from public.daily_questions limit 1;
    insert into public.question_responses (question_id, couple_id, user_id, response)
        values (q, c, a, 'A answer'), (q, c, b, 'B answer');

    perform set_config('test.uid', a::text, false);
    perform public.leave_couple(a);

    -- The existing couple is now A's solo couple; a new solo couple exists for B.
    if not exists (select 1 from public.couples where id = c and solo and partner_a = a and partner_b = a) then
        raise exception 'S2: original couple did not become A solo couple';
    end if;
    select id into d from public.couples where solo and partner_a = b and partner_b = b;
    if d is null then raise exception 'S2: B did not get a solo couple'; end if;

    -- Each partner's OWN rows moved to their own couple; nothing was deleted.
    if (select couple_id from public.reminders where id = r_a) <> c then raise exception 'S2: A reminder left A couple'; end if;
    if (select couple_id from public.reminders where id = r_b) <> d then raise exception 'S2: B reminder did not move to B couple'; end if;

    if (select couple_id from public.reminder_events where reminder_id = r_a) <> c then raise exception 'S2: A event left A couple'; end if;
    if (select couple_id from public.reminder_events where reminder_id = r_b) <> d then raise exception 'S2: B event did not move to B couple'; end if;

    if (select couple_id from public.question_responses where user_id = a) <> c then raise exception 'S2: A check-in left A couple'; end if;
    if (select couple_id from public.question_responses where user_id = b) <> d then raise exception 'S2: B check-in did not move to B couple'; end if;

    -- Shared milestone copied to both couples; total reminders/events/check-ins unchanged.
    select count(*) into n from public.milestones where couple_id in (c, d);
    if n <> 2 then raise exception 'S2: expected milestone on both couples (2), got %', n; end if;
    select count(*) into n from public.reminders where couple_id in (c, d);
    if n <> 2 then raise exception 'S2: reminder count changed, got %', n; end if;
    select count(*) into n from public.reminder_events where couple_id in (c, d);
    if n <> 2 then raise exception 'S2: event count changed, got %', n; end if;
    select count(*) into n from public.question_responses where couple_id in (c, d);
    if n <> 2 then raise exception 'S2: check-in count changed, got %', n; end if;

    raise notice 'S2 leave_couple split: PASS';
end $$;

-- ============================================================
-- Scenario 3 — delete_account: leaver is removed, partner keeps everything
-- ============================================================
do $$
declare
    a uuid := '55555555-5555-5555-5555-555555555555';  -- leaver
    b uuid := '66666666-6666-6666-6666-666666666666';  -- partner (keeps account)
    c uuid;
    r_a uuid; r_b uuid; r_ba uuid;   -- r_ba: authored by B, targets A (cascade landmine)
    q  uuid;
    n int;
begin
    insert into auth.users (id, email) values (a, 'a3@test'), (b, 'b3@test');
    insert into public.couples (partner_a, partner_b, solo) values (a, b, false) returning id into c;

    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, a, a, 'A reminder', 'words', 'one_time') returning id into r_a;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, b, b, 'B reminder', 'acts', 'one_time') returning id into r_b;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, b, a, 'B reminder targeting A', 'gifts', 'one_time') returning id into r_ba;
    insert into public.reminder_events (reminder_id, couple_id) values (r_a, c), (r_b, c), (r_ba, c);
    insert into public.milestones (couple_id, kind, date) values (c, 'anniv', '2023-03-03');

    select id into q from public.daily_questions limit 1;
    insert into public.question_responses (question_id, couple_id, user_id, response)
        values (q, c, a, 'A answer'), (q, c, b, 'B answer');

    perform set_config('test.uid', a::text, false);
    perform public.delete_account(a);

    -- The leaver is gone; the partner's account remains.
    if exists (select 1 from auth.users where id = a) then raise exception 'S3: leaver auth row survived'; end if;
    if not exists (select 1 from auth.users where id = b) then raise exception 'S3: partner auth row was deleted'; end if;

    -- The couple survives as the partner's solo couple.
    if not exists (select 1 from public.couples where id = c and solo and partner_a = b and partner_b = b) then
        raise exception 'S3: couple was not handed to partner as a solo couple';
    end if;

    -- Partner's data is intact, including the reminder that had targeted the leaver
    -- (re-pointed to self so the target_id cascade did not delete it).
    if not exists (select 1 from public.reminders where id = r_b) then raise exception 'S3: partner reminder deleted'; end if;
    if not exists (select 1 from public.reminders where id = r_ba) then raise exception 'S3: partner reminder targeting leaver was deleted'; end if;
    if (select target_id from public.reminders where id = r_ba) <> b then raise exception 'S3: target was not re-pointed to partner'; end if;
    if not exists (select 1 from public.reminder_events where reminder_id = r_b) then raise exception 'S3: partner event deleted'; end if;
    if not exists (select 1 from public.reminder_events where reminder_id = r_ba) then raise exception 'S3: partner (targeting) event deleted'; end if;
    if not exists (select 1 from public.milestones where couple_id = c) then raise exception 'S3: shared milestone deleted'; end if;
    if not exists (select 1 from public.question_responses where user_id = b) then raise exception 'S3: partner check-in deleted'; end if;

    -- The leaver's own data is gone.
    if exists (select 1 from public.reminders where id = r_a) then raise exception 'S3: leaver reminder survived'; end if;
    if exists (select 1 from public.reminder_events where reminder_id = r_a) then raise exception 'S3: leaver event survived'; end if;
    if exists (select 1 from public.question_responses where user_id = a) then raise exception 'S3: leaver check-in survived'; end if;

    -- Net: only the partner's rows remain.
    select count(*) into n from public.reminders where couple_id = c;
    if n <> 2 then raise exception 'S3: expected 2 partner reminders, got %', n; end if;
    select count(*) into n from public.question_responses where couple_id = c;
    if n <> 1 then raise exception 'S3: expected 1 partner check-in, got %', n; end if;

    raise notice 'S3 delete_account preserve partner: PASS';
end $$;

-- ============================================================
-- Scenario 4 — leave_couple is symmetric: same outcome when partner_b calls it
-- ============================================================
do $$
declare
    a uuid := '77777777-7777-7777-7777-777777777777';  -- partner_a
    b uuid := '88888888-8888-8888-8888-888888888888';  -- partner_b (the caller here)
    c uuid;
    r_a uuid; r_b uuid;
begin
    insert into auth.users (id, email) values (a, 'a4@test'), (b, 'b4@test');
    insert into public.couples (partner_a, partner_b, solo) values (a, b, false) returning id into c;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, a, b, 'A reminder', 'words', 'one_time') returning id into r_a;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, b, a, 'B reminder', 'acts', 'one_time') returning id into r_b;

    perform set_config('test.uid', b::text, false);
    perform public.leave_couple(b);

    -- Roles are assigned by partner slot, not by caller: A keeps couple c, B gets a new one.
    if not exists (select 1 from public.couples where id = c and solo and partner_a = a and partner_b = a) then
        raise exception 'S4: caller=B still left A on the original couple as expected — failed';
    end if;
    if (select couple_id from public.reminders where id = r_a) <> c then raise exception 'S4: A reminder moved unexpectedly'; end if;
    if (select couple_id from public.reminders where id = r_b) = c then raise exception 'S4: B reminder did not move off shared couple'; end if;

    raise notice 'S4 leave_couple symmetric (partner_b caller): PASS';
end $$;

-- ============================================================
-- Scenario 5 — delete_account for a solo user just deletes them (no partner)
-- ============================================================
do $$
declare
    a uuid := '99999999-9999-9999-9999-999999999999';
    c uuid;
    r_a uuid;
begin
    insert into auth.users (id, email) values (a, 'a5@test');
    insert into public.couples (partner_a, partner_b, solo) values (a, a, true) returning id into c;
    insert into public.reminders (couple_id, author_id, target_id, title, love_language, trigger_type)
        values (c, a, a, 'Solo reminder', 'words', 'one_time') returning id into r_a;

    perform set_config('test.uid', a::text, false);
    perform public.delete_account(a);

    if exists (select 1 from auth.users where id = a) then raise exception 'S5: solo user not deleted'; end if;
    if exists (select 1 from public.couples where id = c) then raise exception 'S5: solo couple survived'; end if;
    if exists (select 1 from public.reminders where id = r_a) then raise exception 'S5: solo reminder survived'; end if;

    raise notice 'S5 delete_account solo user: PASS';
end $$;

rollback;

\echo 'ALL RPC LIFECYCLE TESTS PASSED'
