/*
  # Add Location Columns to Organizations Table

  1. Changes
    - Add `state` (text) column to `organizations` table
    - Add `lga` (text) column to `organizations` table
  
  2. Notes
    - `address` column already exists in the schema.
*/

DO $$
BEGIN
  -- Add state column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'organizations' AND column_name = 'state'
  ) THEN
    ALTER TABLE organizations ADD COLUMN state text;
    CREATE INDEX idx_organizations_state ON organizations(state);
  END IF;

  -- Add lga column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'organizations' AND column_name = 'lga'
  ) THEN
    ALTER TABLE organizations ADD COLUMN lga text;
    CREATE INDEX idx_organizations_lga ON organizations(lga);
  END IF;

END $$;
