-- Enable extensions if needed
-- create extension if not exists "uuid-ossp";

-- 1. user_profiles table
create table public.user_profiles (
  id uuid primary key references auth.users(id),
  first_name text not null,
  last_name text not null,
  email text not null unique,
  phone text,
  profile_image text,
  created_at timestamp with time zone default now()
);

-- 2. user_activities table
create table public.user_activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  title text not null,
  type text,
  accuracy text,
  created_at timestamp with time zone default now()
);

-- 3. user_achievements table
create table public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  title text not null,
  badge text,
  type text,
  created_at timestamp with time zone default now()
);

-- 4. learning_progress table
create table public.learning_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  module text not null,
  lesson_index int not null,
  completed boolean default false,
  completed_at timestamp with time zone
);

-- 5. daily_stats table
create table public.daily_stats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  date date not null,
  words_learned int default 0,
  translations_made int default 0,
  practice_sessions int default 0
);

-- Enable Row-Level Security
alter table public.user_profiles enable row level security;
alter table public.user_activities enable row level security;
alter table public.user_achievements enable row level security;
alter table public.learning_progress enable row level security;
alter table public.daily_stats enable row level security;

-- RLS policies for user_profiles
create policy "Select own profile" on public.user_profiles for select using (auth.uid() = id);
create policy "Insert own profile" on public.user_profiles for insert with check (auth.uid() = id);
create policy "Update own profile" on public.user_profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "Delete own profile" on public.user_profiles for delete using (auth.uid() = id);

-- RLS policies for other tables (example for activities)
create policy "Manage own activities" on public.user_activities for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Manage own achievements" on public.user_achievements for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Manage own learning_progress" on public.learning_progress for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Manage own daily_stats" on public.daily_stats for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
