-- Add attachments column to cases table
ALTER TABLE cases ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT '[]'::jsonb;
