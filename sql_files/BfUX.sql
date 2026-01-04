-- ============================================================================
-- FIX CASE ASSIGNMENT PERMISSIONS
-- Purpose: 
-- 1. Ensure Admins can UPDATE any case (specifically 'assigned_to').
-- 2. Verify and fix RLS policies for the 'cases' table.
-- ============================================================================

-- 1. Drop restrictve policies if they exist (to be safe)
DROP POLICY IF EXISTS "Admins can update all cases" ON cases;
DROP POLICY IF EXISTS "Organizations can update assigned cases" ON cases;

-- 2. Create permissive policy for Admins
CREATE POLICY "Admins can update all cases"
ON cases FOR UPDATE
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
)
WITH CHECK (
  (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
);

-- 3. Create policy for Organization users (Only their own cases)
CREATE POLICY "Organizations can update assigned cases"
ON cases FOR UPDATE
TO authenticated
USING (
  assigned_to = (SELECT organization_name FROM public.users WHERE id = auth.uid()) OR
  created_by = auth.uid()
)
WITH CHECK (
  assigned_to = (SELECT organization_name FROM public.users WHERE id = auth.uid()) OR
  created_by = auth.uid()
);

-- 4. Enable RLS (just in case)
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- 5. Helper verification
DO $$
BEGIN
  RAISE NOTICE 'Case Assignment Policies Updated. Admins can now assign cases freely.';
END $$;
