-- Premium features: daily check-in questions, reminder events helpers

-- Daily Questions (question bank)
create table public.daily_questions (
    id          uuid primary key default gen_random_uuid(),
    question    text not null,
    category    text not null default 'general',
    love_language text check (love_language in ('words','acts','gifts','time','touch', null)),
    created_at  timestamptz not null default now()
);

alter table public.daily_questions enable row level security;
create policy "daily_questions_read"
    on public.daily_questions for select using (true);

-- Question Responses
create table public.question_responses (
    id          uuid primary key default gen_random_uuid(),
    question_id uuid not null references public.daily_questions(id) on delete cascade,
    couple_id   uuid not null references public.couples(id) on delete cascade,
    user_id     uuid not null references public.profiles(id) on delete cascade,
    response    text not null,
    created_at  timestamptz not null default now(),
    unique (question_id, couple_id, user_id)
);

create index question_responses_couple_idx on public.question_responses(couple_id, created_at desc);

alter table public.question_responses enable row level security;

create policy "question_responses_member_rw"
    on public.question_responses for all
    using (public.is_couple_member(couple_id))
    with check (public.is_couple_member(couple_id) and user_id = auth.uid());

-- Seed questions
insert into public.daily_questions (question, category, love_language) values
    ('What is one thing you appreciated about your partner today?', 'appreciation', 'words'),
    ('What is a compliment you received recently that meant a lot?', 'gratitude', 'words'),
    ('Write a short affirmation for your partner.', 'affirmation', 'words'),
    ('What is something your partner said recently that made you smile?', 'gratitude', 'words'),
    ('Share a memory of a time your partner''s words encouraged you.', 'reflection', 'words'),
    ('What is one act of kindness you could do for your partner this week?', 'service', 'acts'),
    ('What is a task your partner did for you that you are grateful for?', 'gratitude', 'acts'),
    ('If you had an extra hour today, what would you do to help your partner?', 'service', 'acts'),
    ('What household task do you most appreciate your partner handling?', 'appreciation', 'acts'),
    ('What is the best gift you have ever received from your partner?', 'reflection', 'gifts'),
    ('What is a small thoughtful gesture you could surprise your partner with?', 'surprise', 'gifts'),
    ('Describe a gift that made you feel truly seen and understood.', 'reflection', 'gifts'),
    ('What is one thing you would love to do together this weekend?', 'planning', 'time'),
    ('Describe your ideal date night.', 'fun', 'time'),
    ('What is a shared hobby you want to explore together?', 'fun', 'time'),
    ('When did you last feel completely present with your partner?', 'reflection', 'time'),
    ('What is a place you both love to go together?', 'nostalgia', 'time'),
    ('What is your favorite way to be comforted by your partner?', 'intimacy', 'touch'),
    ('Describe a moment when a simple touch from your partner meant everything.', 'reflection', 'touch'),
    ('What is a small physical gesture that makes you feel loved?', 'intimacy', 'touch'),
    ('What is one thing you want your partner to know today?', 'general', null),
    ('What relationship goal do you want to work on together?', 'goals', null),
    ('Describe your favorite memory together as a couple.', 'nostalgia', null),
    ('What is something new you have learned about your partner recently?', 'discovery', null),
    ('If you could plan a surprise for your partner, what would it be?', 'planning', null),
    ('What is a quality you admire most in your partner?', 'appreciation', null),
    ('What song reminds you of your partner, and why?', 'fun', null),
    ('What is one thing you want to accomplish as a couple this year?', 'goals', null),
    ('Describe a challenge you overcame together and what it taught you.', 'reflection', null),
    ('What is the funniest moment you have shared recently?', 'fun', null);
