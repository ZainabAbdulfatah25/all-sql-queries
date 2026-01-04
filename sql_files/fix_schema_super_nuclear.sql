-- ============================================================================
-- FIX SCHEMA SUPER NUCLEAR (DYNAMIC DROP ALL POLICIES)
-- Purpose: 
-- 1. Dynamically find and drop ALL policies on 'cases' and 'registrations'.
-- 2. Alter column types to TEXT.
-- 3. Recreate Policies and Update Data.
-- ============================================================================

-- A. DYNAMIC DROP ALL POLICIES (Cases)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'cases'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON cases', r.policyname);
        RAISE NOTICE 'Dropped policy on cases: %', r.policyname;
    END LOOP;
END $$;

-- B. DYNAMIC DROP ALL POLICIES (Registrations)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'registrations'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON registrations', r.policyname);
        RAISE NOTICE 'Dropped policy on registrations: %', r.policyname;
    END LOOP;
END $$;


-- C. DROP CONSTRAINTS & ALTER SCHEMA (Cases)
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT conname FROM pg_constraint WHERE conrelid = 'cases'::regclass AND conkey[1] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'cases'::regclass AND attname = 'assigned_to')
    LOOP
        EXECUTE 'ALTER TABLE cases DROP CONSTRAINT ' || quote_ident(r.conname);
        RAISE NOTICE 'Dropped constraint: %', r.conname;
    END LOOP;
END $$;

ALTER TABLE cases ALTER COLUMN assigned_to TYPE TEXT USING assigned_to::text;


-- D. DROP CONSTRAINTS & ALTER SCHEMA (Registrations)
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT conname FROM pg_constraint WHERE conrelid = 'registrations'::regclass AND conkey[1] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'registrations'::regclass AND attname = 'assigned_organization')
    LOOP
        EXECUTE 'ALTER TABLE registrations DROP CONSTRAINT ' || quote_ident(r.conname);
        RAISE NOTICE 'Dropped constraint: %', r.conname;
    END LOOP;
END $$;

ALTER TABLE registrations ALTER COLUMN assigned_organization TYPE TEXT USING assigned_organization::text;


-- E. RE-CREATE RLS POLICIES (Safe V3 policies)
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


-- F. UPDATE DATA
UPDATE cases 
SET assigned_to = 'Defensera', assigned_to_type = 'organization', updated_at = now() 
WHERE case_number = 'CASE-1766977040541-HSSXX';

UPDATE registrations 
SET assigned_organization = 'Defensera', assignment_date = now() 
WHERE id IN (SELECT registration_id FROM cases WHERE case_number = 'CASE-1766977040541-HSSXX');

DO $$
BEGIN
  RAISE NOTICE 'Schema cleanup complete. All policies dropped, schema altered to TEXT, policies restored, and data updated.';
END $$;
