-- ============================================================================
-- FIX CASE RLS V3 (UNIVERSAL TYPE CASTING)
-- Purpose: 
-- 1. Force ALL comparisons to be TEXT vs TEXT to bypass "uuid = text" errors.
-- 2. Ensure Schema flexibility (works whether columns are UUID or Text).
-- ============================================================================

-- 1. Drop EVERYTHING again
DROP POLICY IF EXISTS "Unified Read Policy" ON cases;
DROP POLICY IF EXISTS "Unified Insert Policy" ON cases;
DROP POLICY IF EXISTS "Unified Update Policy" ON cases;
DROP POLICY IF EXISTS "Unified Delete Policy" ON cases;
DROP POLICY IF EXISTS "Admins can update all cases" ON cases;
DROP POLICY IF EXISTS "Organizations can update assigned cases" ON cases;
DROP POLICY IF EXISTS "Enable read access for all users" ON cases;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON cases;

-- 2. Force Enable RLS
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- 3. Create READ Policy (Universal Casting)
CREATE POLICY "Unified Read Policy"
ON cases FOR SELECT
TO authenticated
USING (
  -- Admin Check (Cast ID to text)
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Creator Check (Cast created_by to text)
  created_by::text = auth.uid()::text
  OR
  -- Assignment Check (Cast assigned_to to text)
  assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);

-- 4. Create INSERT Policy
CREATE POLICY "Unified Insert Policy"
ON cases FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
);

-- 5. Create UPDATE Policy
CREATE POLICY "Unified Update Policy"
ON cases FOR UPDATE
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR
  created_by::text = auth.uid()::text
  OR
  assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
)
WITH CHECK (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR
  created_by::text = auth.uid()::text
  OR
  assigned_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);

-- 6. Create DELETE Policy
CREATE POLICY "Unified Delete Policy"
ON cases FOR DELETE
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
);

DO $$
BEGIN
  RAISE NOTICE 'Applied V3 RLS policies with universal TEXT casting.';
END $$;
