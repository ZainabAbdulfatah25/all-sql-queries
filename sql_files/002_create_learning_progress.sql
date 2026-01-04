-- Create learning progress table
create table if not exists public.learning_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  module_name text not null,
  completed boolean default false,
  progress_percentage integer default 0,
  last_accessed timestamp with time zone default now(),
  created_at timestamp with time zone default now(),
  unique(user_id, module_name)
);

alter table public.learning_progress enable row level security;

-- Learning progress policies
create policy "learning_progress_select_own"
  on public.learning_progress for select
  using (auth.uid() = user_id);

create policy "learning_progress_insert_own"
  on public.learning_progress for insert
  with check (auth.uid() = user_id);

create policy "learning_progress_update_own"
  on public.learning_progress for update
  using (auth.uid() = user_id);

create policy "learning_progress_delete_own"
  on public.learning_progress for delete
  using (auth.uid() = user_id);
