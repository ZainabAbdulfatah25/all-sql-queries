-- INSERT Buckets into storage.buckets
-- This ensures the buckets exist so that the policies we created can actually apply to something.

-- 1. Create 'case-attachments' bucket
insert into storage.buckets (id, name, public)
values ('case-attachments', 'case-attachments', true)
on conflict (id) do update set public = true;

-- 2. Create 'registration-attachments' bucket
insert into storage.buckets (id, name, public)
values ('registration-attachments', 'registration-attachments', true)
on conflict (id) do update set public = true;

-- 3. Re-apply policies (just to be safe, ensuring RLS doesn't block the new buckets)

-- Drop existing policies to avoid duplicates (optional, but cleaner)
drop policy if exists "Public Access to Case Attachments" on storage.objects;
drop policy if exists "Authenticated Users can Upload Case Attachments" on storage.objects;
drop policy if exists "Users can update own Case Attachments" on storage.objects;
drop policy if exists "Users can delete own Case Attachments" on storage.objects;

drop policy if exists "Public Access to Registration Attachments" on storage.objects;
drop policy if exists "Authenticated Users can Upload Registration Attachments" on storage.objects;
drop policy if exists "Users can update own Registration Attachments" on storage.objects;
drop policy if exists "Users can delete own Registration Attachments" on storage.objects;

-- Re-create Policies for 'case-attachments'
create policy "Public Access to Case Attachments"
on storage.objects for select
using ( bucket_id = 'case-attachments' );

create policy "Authenticated Users can Upload Case Attachments"
on storage.objects for insert
with check ( bucket_id = 'case-attachments' and auth.role() = 'authenticated' );

create policy "Users can update own Case Attachments"
on storage.objects for update
using ( bucket_id = 'case-attachments' and auth.uid() = owner );

create policy "Users can delete own Case Attachments"
on storage.objects for delete
using ( bucket_id = 'case-attachments' and auth.uid() = owner );

-- Re-create Policies for 'registration-attachments'
create policy "Public Access to Registration Attachments"
on storage.objects for select
using ( bucket_id = 'registration-attachments' );

create policy "Authenticated Users can Upload Registration Attachments"
on storage.objects for insert
with check ( bucket_id = 'registration-attachments' and auth.role() = 'authenticated' );

create policy "Users can update own Registration Attachments"
on storage.objects for update
using ( bucket_id = 'registration-attachments' and auth.uid() = owner );

create policy "Users can delete own Registration Attachments"
on storage.objects for delete
using ( bucket_id = 'registration-attachments' and auth.uid() = owner );
