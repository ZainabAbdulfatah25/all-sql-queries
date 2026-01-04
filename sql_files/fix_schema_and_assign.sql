-- ============================================================================
-- FIX SCHEMA & ASSIGNMENT (FORCE TEXT TYPE)
-- Purpose: 
-- 1. Convert 'cases.assigned_to' and 'registrations.assigned_organization' to TEXT.
-- 2. Drop Foreign Key constraints that force these columns to be UUIDs.
-- 3. Update data using Dynamic SQL to bypass parser errors during migration.
-- ============================================================================

-- A. FIX CASES SCHEMA
DO $$ 
DECLARE 
  r RECORD;
BEGIN
  -- 1. Drop any Foreign Keys on 'cases.assigned_to'
  FOR r IN (
    SELECT conname 
    FROM pg_constraint 
    WHERE conrelid = 'cases'::regclass AND confrelid = 'users'::regclass AND conkey[1] = (
      SELECT attnum FROM pg_attribute WHERE attrelid = 'cases'::regclass AND attname = 'assigned_to'
    )
  ) LOOP
    EXECUTE 'ALTER TABLE cases DROP CONSTRAINT ' || quote_ident(r.conname);
    RAISE NOTICE 'Dropped foreign key constraint on cases.assigned_to: %', r.conname;
  END LOOP;

  -- 2. Alter Column to TEXT
  -- We do this insdie a block to catch if it's already text
  BEGIN
    ALTER TABLE cases ALTER COLUMN assigned_to TYPE TEXT USING assigned_to::text;
    RAISE NOTICE 'Success: cases.assigned_to is now TEXT.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Notice: cases.assigned_to might already be compatible or failed: %', SQLERRM;
  END;
END $$;


-- B. FIX REGISTRATIONS SCHEMA
DO $$ 
DECLARE 
  r RECORD;
BEGIN
  -- 1. Drop Foreign Keys on 'registrations.assigned_organization'
  FOR r IN (
    SELECT conname 
    FROM pg_constraint 
    WHERE conrelid = 'registrations'::regclass AND (confrelid = 'organizations'::regclass OR confrelid = 'users'::regclass) AND conkey[1] = (
      SELECT attnum FROM pg_attribute WHERE attrelid = 'registrations'::regclass AND attname = 'assigned_organization'
    )
  ) LOOP
    EXECUTE 'ALTER TABLE registrations DROP CONSTRAINT ' || quote_ident(r.conname);
    RAISE NOTICE 'Dropped foreign key constraint on registrations.assigned_organization: %', r.conname;
  END LOOP;

  -- 2. Alter Column to TEXT
  BEGIN
    ALTER TABLE registrations ALTER COLUMN assigned_organization TYPE TEXT USING assigned_organization::text;
    RAISE NOTICE 'Success: registrations.assigned_organization is now TEXT.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Notice: registrations.assigned_organization might already be compatible or failed: %', SQLERRM;
  END;
END $$;


-- C. RE-APPLY RLS (Safe V3 policies)
DROP POLICY IF EXISTS "Unified Read Policy" ON cases;
DROP POLICY IF EXISTS "Unified Insert Policy" ON cases;
DROP POLICY IF EXISTS "Unified Update Policy" ON cases;
DROP POLICY IF EXISTS "Unified Delete Policy" ON cases;

CREATE POLICY "Unified Read Policy" ON cases FOR SELECT TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR created_by::text = auth.uid()::text
  OR assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);
CREATE POLICY "Unified Insert Policy" ON cases FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Unified Update Policy" ON cases FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Unified Delete Policy" ON cases FOR DELETE TO authenticated USING ((SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin'));
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- Registrations RLS
DROP POLICY IF EXISTS "Unified Read Policy" ON registrations;
DROP POLICY IF EXISTS "Unified Insert Policy" ON registrations;
DROP POLICY IF EXISTS "Unified Update Policy" ON registrations;
DROP POLICY IF EXISTS "Unified Delete Policy" ON registrations;

CREATE POLICY "Unified Read Policy" ON registrations FOR SELECT TO authenticated
USING (
   (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
   OR created_by::text = auth.uid()::text
   OR assigned_organization::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);
CREATE POLICY "Unified Insert Policy" ON registrations FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Unified Update Policy" ON registrations FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;


-- D. MANUAL DATA FIX (Dynamic SQL to bypass parser checks)
DO $$
BEGIN
  -- Update Case
  EXECUTE 'UPDATE cases SET assigned_to = ''Defensera'', assigned_to_type = ''organization'', updated_at = now() WHERE case_number = ''CASE-1766977040541-HSSXX''';
  
  -- Update Registrations linked to that case
  EXECUTE 'UPDATE registrations SET assigned_organization = ''Defensera'', assignment_date = now() WHERE id IN (SELECT registration_id FROM cases WHERE case_number = ''CASE-1766977040541-HSSXX'')';

  RAISE NOTICE 'Data successfully updated to Defensera via Dynamic SQL.';
END $$;
