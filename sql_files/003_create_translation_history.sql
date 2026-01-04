-- Create translation history table
create table if not exists public.translation_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  type text not null check (type in ('voice-to-sign', 'sign-to-text', 'text-to-sign')),
  input_text text,
  output_text text,
  language text default 'english',
  created_at timestamp with time zone default now()
);

alter table public.translation_history enable row level security;

-- Translation history policies
create policy "translation_history_select_own"
  on public.translation_history for select
  using (auth.uid() = user_id);

create policy "translation_history_insert_own"
  on public.translation_history for insert
  with check (auth.uid() = user_id);

create policy "translation_history_delete_own"
  on public.translation_history for delete
  using (auth.uid() = user_id);
