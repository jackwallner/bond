-- Unpair has to stop delivery. leave_couple only moves couple_id, which the queue
-- trigger ignored, and the claim checked nothing about the couple, so a recurring or
-- future reminder kept reaching an ex's phone, and every edit by the ex reached it too.
--
-- A push now needs both the author and the target to be the two partners of the
-- reminder's couple. That is checked when a row enters the queue and again when it is
-- claimed, and any change to a couple re-reads its reminders, so pairing again brings
-- them back.

create function public.reminder_pair_intact(r public.reminders)
returns boolean
language sql stable
set search_path = public
as $$
    select exists (
        select 1 from public.couples c
         where c.id = r.couple_id
           and not c.solo
           and r.author_id in (c.partner_a, c.partner_b)
           and r.target_id in (c.partner_a, c.partner_b)
    );
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
        insert into public.reminder_push_queue (reminder_id, next_push_at, silent)
        values (r.id, next_at, false)
        on conflict (reminder_id) do update
            set next_push_at = excluded.next_push_at, silent = false;
    end if;
end;
$$;

create or replace function public.reminders_sync_push_queue()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    if new.trigger_type = 'location'
       and new.target_id <> new.author_id
       and not new.surprise_hidden_from_partner
       and public.reminder_pair_intact(new) then
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

drop trigger reminders_sync_push_queue on public.reminders;

create trigger reminders_sync_push_queue
    after insert or update of couple_id, fire_at, rrule, geofence, window_start, window_end,
        trigger_type, author_id, target_id, surprise_hidden_from_partner
    on public.reminders
    for each row execute function public.reminders_sync_push_queue();

-- A failure here must never cost anyone an unpair or a pairing, so it warns and moves on.
create function public.couples_sync_push_queue()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
    r public.reminders;
begin
    for r in
        select * from public.reminders x
         where x.couple_id = new.id and x.author_id <> x.target_id
    loop
        perform public.refresh_reminder_push(r);
    end loop;
    return new;
exception when others then
    raise warning 'reminder push queue not updated for couple %: %', new.id, sqlerrm;
    return new;
end;
$$;

create trigger couples_sync_push_queue
    after update of partner_a, partner_b, solo
    on public.couples
    for each row execute function public.couples_sync_push_queue();

create or replace function public.claim_due_reminder_pushes(p_limit int default 200)
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

        if not public.reminder_pair_intact(r) then
            delete from public.reminder_push_queue pq where pq.reminder_id = r.id;
            continue;
        end if;

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

revoke all on function public.reminder_pair_intact(public.reminders) from public;
revoke all on function public.couples_sync_push_queue() from public;
revoke all on function public.refresh_reminder_push(public.reminders) from public;
revoke all on function public.reminders_sync_push_queue() from public;
revoke all on function public.claim_due_reminder_pushes(int) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.claim_due_reminder_pushes(int) to service_role;
    end if;
end
$$;

-- Couples that already split, or rows queued for someone no longer a partner.
delete from public.reminder_push_queue pq
 using public.reminders r
 where r.id = pq.reminder_id
   and not public.reminder_pair_intact(r);
