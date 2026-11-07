-- A lease now outlasts the longest run of send-push (150 s), so a slow run can't
-- have its rows claimed a second time while it is still recording them.
--
-- Removing a dead token reports false only while the phone is still registered for
-- that user. Two rows in one batch can share a dead token, and the second finds it
-- already gone.

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
                   set lease_until = now() + interval '3 minutes'
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
               set lease_until = now() + interval '3 minutes'
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

create or replace function public.remove_dead_push_device(p_token text, p_user uuid, p_seen timestamptz)
returns boolean
language sql
security definer set search_path = public
as $$
    with gone as (
        delete from public.push_devices
         where token = p_token and user_id = p_user and updated_at = p_seen
        returning 1
    )
    select exists (select 1 from gone)
        or not exists (select 1 from public.push_devices where token = p_token and user_id = p_user);
$$;

notify pgrst, 'reload schema';
