-- ============================================================================
-- FIX CASE SCHEMA & DATA TYPES & RE-APPLY RLS
-- Purpose: 
-- 1. Ensure 'assigned_to' column is TEXT (not UUID) to support Org Names like 'Defensera'.
-- 2. Re-apply V3 RLS Policies (Universal Casting) for safety.
-- 3. Force-update the specific disputed case to 'Defensera'.
-- ============================================================================

-- 1. Alter Schema (Safeguard)
-- If 'assigned_to' is UUID, this change allows it to store Organization Names strings.
DO $$
BEGIN
  -- Attempt to alter column type to TEXT if it isn't already
  -- We use a safe cast. If data is incompatible, it might fail, but for now we assume it's okay or empty.
  BEGIN
    ALTER TABLE cases ALTER COLUMN assigned_to TYPE TEXT USING assigned_to::text;
    RAISE NOTICE 'Confirmed assigned_to is TEXT.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not alter assigned_to to TEXT directly: %', SQLERRM;
  END;
END $$;

-- 2. Drop & Recreate RLS (V3 Universal Logic)
DROP POLICY IF EXISTS "Unified Read Policy" ON cases;
DROP POLICY IF EXISTS "Unified Insert Policy" ON cases;
DROP POLICY IF EXISTS "Unified Update Policy" ON cases;
DROP POLICY IF EXISTS "Unified Delete Policy" ON cases;

CREATE POLICY "Unified Read Policy"
ON cases FOR SELECT
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR created_by::text = auth.uid()::text
  OR assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);

CREATE POLICY "Unified Insert Policy"
ON cases FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Unified Update Policy"
ON cases FOR UPDATE
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR created_by::text = auth.uid()::text
  OR assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
)
WITH CHECK (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR created_by::text = auth.uid()::text
  OR assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);

CREATE POLICY "Unified Delete Policy"
ON cases FOR DELETE TO authenticated
USING ((SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin'));

ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- 3. Force Update the Case (Manual Fix)
-- Updates CASE-1766977040541-HSSXX to 'Defensera'
UPDATE cases 
SET 
  assigned_to = 'Defensera', 
  assigned_to_type = 'organization',
  updated_at = now()
WHERE case_number = 'CASE-1766977040541-HSSXX';

DO $$
BEGIN
  RAISE NOTICE 'Schema checked, RLS applied, and Case manually assigned to Defensera.';
END $$;
