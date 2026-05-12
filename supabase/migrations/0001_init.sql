-- Bond initial schema
-- Run via: supabase db push  (or apply through MCP apply_migration)

create extension if not exists "pgcrypto";

-- ============================================================
-- Profiles
-- ============================================================
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    avatar_url   text,
    apns_token   text,
    created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_self_upsert"
    on public.profiles for insert with check (id = auth.uid());
create policy "profiles_self_update"
    on public.profiles for update using (id = auth.uid());
-- "profiles_self_select" is defined after `couples` exists (below).

-- Auto-create a profile row when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ============================================================
-- Couples
-- ============================================================
create table public.couples (
    id          uuid primary key default gen_random_uuid(),
    partner_a   uuid not null references public.profiles(id) on delete cascade,
    partner_b   uuid not null references public.profiles(id) on delete cascade,
    paired_at   timestamptz not null default now(),
    constraint couples_partners_distinct check (partner_a <> partner_b)
);

create unique index couples_partner_a_idx on public.couples(partner_a);
create unique index couples_partner_b_idx on public.couples(partner_b);

alter table public.couples enable row level security;

create policy "couples_members_select"
    on public.couples for select
    using (partner_a = auth.uid() or partner_b = auth.uid());

-- Now that `couples` exists, the partner-visible profile policy can reference it.
create policy "profiles_self_select"
    on public.profiles for select
    using (
        id = auth.uid()
        or id in (
            select case when partner_a = auth.uid() then partner_b else partner_a end
            from public.couples
            where partner_a = auth.uid() or partner_b = auth.uid()
        )
    );

-- ============================================================
-- Invite codes (pairing)
-- ============================================================
create table public.invite_codes (
    code        text primary key,
    created_by  uuid not null references public.profiles(id) on delete cascade,
    expires_at  timestamptz not null,
    created_at  timestamptz not null default now()
);

alter table public.invite_codes enable row level security;

create policy "invite_codes_owner_select"
    on public.invite_codes for select
    using (created_by = auth.uid());
create policy "invite_codes_owner_insert"
    on public.invite_codes for insert
    with check (created_by = auth.uid());

-- Consume an invite code: pairs current user with the inviter.
create or replace function public.consume_invite_code(p_code text, p_user uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    v_inviter uuid;
    v_couple_id uuid;
begin
    if p_user <> auth.uid() then
        raise exception 'unauthorized';
    end if;

    select created_by into v_inviter
    from public.invite_codes
    where code = p_code and expires_at > now()
    for update;

    if v_inviter is null then
        raise exception 'invalid or expired code';
    end if;
    if v_inviter = p_user then
        raise exception 'cannot pair with yourself';
    end if;

    insert into public.couples (partner_a, partner_b)
    values (v_inviter, p_user)
    returning id into v_couple_id;

    delete from public.invite_codes where code = p_code;

    return v_couple_id;
end;
$$;

grant execute on function public.consume_invite_code(text, uuid) to authenticated;

-- ============================================================
-- Reminders
-- ============================================================
create table public.reminders (
    id            uuid primary key default gen_random_uuid(),
    couple_id     uuid not null references public.couples(id) on delete cascade,
    author_id     uuid not null references public.profiles(id) on delete cascade,
    target_id     uuid not null references public.profiles(id) on delete cascade,
    title         text not null,
    body          text,
    love_language text not null check (love_language in ('words','acts','gifts','time','touch')),
    trigger_type  text not null check (trigger_type in ('one_time','recurring','location','random_window')),
    fire_at       timestamptz,
    rrule         text,
    geofence      jsonb,
    window_start  timestamptz,
    window_end    timestamptz,
    status        text not null default 'scheduled',
    surprise_hidden_from_partner boolean not null default false,
    created_at    timestamptz not null default now()
);

create index reminders_couple_idx on public.reminders(couple_id);
create index reminders_target_fire_idx on public.reminders(target_id, fire_at);

alter table public.reminders enable row level security;

-- Helper: am I in this couple?
create or replace function public.is_couple_member(p_couple_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.couples
        where id = p_couple_id
          and (partner_a = auth.uid() or partner_b = auth.uid())
    );
$$;

create policy "reminders_member_select"
    on public.reminders for select
    using (
        public.is_couple_member(couple_id)
        and (
            not surprise_hidden_from_partner
            or author_id = auth.uid()
        )
    );

create policy "reminders_member_insert"
    on public.reminders for insert
    with check (
        public.is_couple_member(couple_id)
        and author_id = auth.uid()
    );

create policy "reminders_author_update"
    on public.reminders for update
    using (author_id = auth.uid());

create policy "reminders_author_delete"
    on public.reminders for delete
    using (author_id = auth.uid());

-- ============================================================
-- Reminder events (firing log, for stats/streaks)
-- ============================================================
create table public.reminder_events (
    id           uuid primary key default gen_random_uuid(),
    reminder_id  uuid not null references public.reminders(id) on delete cascade,
    couple_id    uuid not null references public.couples(id) on delete cascade,
    fired_at     timestamptz not null default now(),
    acted_at     timestamptz,
    reaction     text
);

create index reminder_events_couple_fired_idx on public.reminder_events(couple_id, fired_at);

alter table public.reminder_events enable row level security;

create policy "reminder_events_member_rw"
    on public.reminder_events for all
    using (public.is_couple_member(couple_id))
    with check (public.is_couple_member(couple_id));

-- ============================================================
-- Milestones (anniversaries, birthdays)
-- ============================================================
create table public.milestones (
    id         uuid primary key default gen_random_uuid(),
    couple_id  uuid not null references public.couples(id) on delete cascade,
    kind       text not null,
    label      text,
    date       date not null,
    recur      boolean not null default true,
    created_at timestamptz not null default now()
);

create index milestones_couple_idx on public.milestones(couple_id);

alter table public.milestones enable row level security;

create policy "milestones_member_rw"
    on public.milestones for all
    using (public.is_couple_member(couple_id))
    with check (public.is_couple_member(couple_id));

-- ============================================================
-- Subscriptions (StoreKit mirror)
-- ============================================================
create table public.subscriptions (
    user_id       uuid primary key references public.profiles(id) on delete cascade,
    tier          text not null default 'free',
    expires_at    timestamptz,
    store_txn_id  text,
    updated_at    timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

create policy "subscriptions_self_select"
    on public.subscriptions for select using (user_id = auth.uid());
create policy "subscriptions_self_upsert"
    on public.subscriptions for insert with check (user_id = auth.uid());
create policy "subscriptions_self_update"
    on public.subscriptions for update using (user_id = auth.uid());

-- ============================================================
-- AI usage (rate limiting)
-- ============================================================
create table public.ai_usage (
    user_id    uuid not null references public.profiles(id) on delete cascade,
    day        date not null default current_date,
    rewrites   integer not null default 0,
    suggests   integer not null default 0,
    primary key (user_id, day)
);

alter table public.ai_usage enable row level security;
create policy "ai_usage_self_rw"
    on public.ai_usage for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());
