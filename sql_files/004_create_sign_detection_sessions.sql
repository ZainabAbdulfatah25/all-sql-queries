-- Create sign detection sessions table
create table if not exists public.sign_detection_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  detected_signs text[],
  detected_text text,
  confidence_scores jsonb,
  duration_seconds integer,
  created_at timestamp with time zone default now()
);

alter table public.sign_detection_sessions enable row level security;

-- Sign detection sessions policies
create policy "sign_detection_sessions_select_own"
  on public.sign_detection_sessions for select
  using (auth.uid() = user_id);

create policy "sign_detection_sessions_insert_own"
  on public.sign_detection_sessions for insert
  with check (auth.uid() = user_id);

create policy "sign_detection_sessions_delete_own"
  on public.sign_detection_sessions for delete
  using (auth.uid() = user_id);
