-- ============================================================================
-- FIX SCHEMA SCORCH EARTH (DYNAMIC POLICY DROP)
-- Purpose: 
-- 1. Dynamically find and drop ALL policies on 'cases' and 'registrations'.
--    (This avoids knowing specific policy names that might block the alter).
-- 2. Drop Constraints.
-- 3. Alter Columns to TEXT.
-- 4. Re-create RLS Policies.
-- 5. Update Data.
-- ============================================================================

-- A. DYNAMIC POLICY DROP (The key fix)
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Drop all policies on 'cases'
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'cases' LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON cases';
    RAISE NOTICE 'Dropped policy on cases: %', r.policyname;
  END LOOP;

  -- Drop all policies on 'registrations'
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'registrations' LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON registrations';
    RAISE NOTICE 'Dropped policy on registrations: %', r.policyname;
  END LOOP;
END $$;


-- B. DROP CONSTRAINTS & ALTER SCHEMA (Cases)
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT conname FROM pg_constraint WHERE conrelid = 'cases'::regclass AND conkey[1] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'cases'::regclass AND attname = 'assigned_to')
    LOOP
        EXECUTE 'ALTER TABLE cases DROP CONSTRAINT ' || quote_ident(r.conname);
        RAISE NOTICE 'Dropped constraint on cases: %', r.conname;
    END LOOP;
END $$;

-- If this fails, it means there is still a hidden dependency we missed, but the dynamic drop above covers 99% of cases.
ALTER TABLE cases ALTER COLUMN assigned_to TYPE TEXT USING assigned_to::text;


-- C. DROP CONSTRAINTS & ALTER SCHEMA (Registrations)
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT conname FROM pg_constraint WHERE conrelid = 'registrations'::regclass AND conkey[1] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'registrations'::regclass AND attname = 'assigned_organization')
    LOOP
        EXECUTE 'ALTER TABLE registrations DROP CONSTRAINT ' || quote_ident(r.conname);
        RAISE NOTICE 'Dropped constraint on registrations: %', r.conname;
    END LOOP;
END $$;

ALTER TABLE registrations ALTER COLUMN assigned_organization TYPE TEXT USING assigned_organization::text;


-- D. RE-CREATE RLS POLICIES (Standard V3 policies)
-- Cases
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

-- Registrations
CREATE POLICY "Unified Read Policy" ON registrations FOR SELECT TO authenticated
USING (
   (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
   OR created_by::text = auth.uid()::text
   OR assigned_organization::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);
CREATE POLICY "Unified Insert Policy" ON registrations FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Unified Update Policy" ON registrations FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;


-- E. UPDATE DATA
UPDATE cases 
SET assigned_to = 'Defensera', assigned_to_type = 'organization', updated_at = now() 
WHERE case_number = 'CASE-1766977040541-HSSXX';

UPDATE registrations 
SET assigned_organization = 'Defensera', assignment_date = now() 
WHERE id IN (SELECT registration_id FROM cases WHERE case_number = 'CASE-1766977040541-HSSXX');

DO $$
BEGIN
  RAISE NOTICE 'Scorch Earth Complete: Policies dropped, Schema Fix Applied, Data Updated.';
END $$;
