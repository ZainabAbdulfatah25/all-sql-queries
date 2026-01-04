-- Enable the storage extension if not already enabled (usually enabled by default)

-- 1. Create buckets if they don't exist (This is usually done in the dashboard, but we can try inserting if we have permissions, 
-- or at least set up the policies so that if they exist, they work).
-- Note: You generally cannot create buckets via SQL in Supabase default setup easily without specific extensions, 
-- but we can creating policies that ALLOW uploads to these buckets.

-- POLICIES FOR 'case-attachments'

-- Allow public read access to case-attachments
create policy "Public Access to Case Attachments"
on storage.objects for select
using ( bucket_id = 'case-attachments' );

-- Allow authenticated users to upload to case-attachments
create policy "Authenticated Users can Upload Case Attachments"
on storage.objects for insert
with check ( bucket_id = 'case-attachments' and auth.role() = 'authenticated' );

-- Allow users to update/delete their own uploads (optional, but good practice)
create policy "Users can update own Case Attachments"
on storage.objects for update
using ( bucket_id = 'case-attachments' and auth.uid() = owner );

create policy "Users can delete own Case Attachments"
on storage.objects for delete
using ( bucket_id = 'case-attachments' and auth.uid() = owner );


-- POLICIES FOR 'registration-attachments'

-- Allow public read access to registration-attachments
create policy "Public Access to Registration Attachments"
on storage.objects for select
using ( bucket_id = 'registration-attachments' );

-- Allow authenticated users to upload to registration-attachments
create policy "Authenticated Users can Upload Registration Attachments"
on storage.objects for insert
with check ( bucket_id = 'registration-attachments' and auth.role() = 'authenticated' );

-- Allow users to update/delete their own uploads
create policy "Users can update own Registration Attachments"
on storage.objects for update
using ( bucket_id = 'registration-attachments' and auth.uid() = owner );

create policy "Users can delete own Registration Attachments"
on storage.objects for delete
using ( bucket_id = 'registration-attachments' and auth.uid() = owner );
