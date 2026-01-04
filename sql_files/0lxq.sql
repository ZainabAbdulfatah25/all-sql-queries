-- Add attachments column to registrations table
alter table registrations 
add column if not exists attachments jsonb default '[]'::jsonb;
