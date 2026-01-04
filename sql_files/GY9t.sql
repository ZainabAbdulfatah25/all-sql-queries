-- ============================================================================
-- FIX CASE RLS CASTING & PERMISSIONS
-- Purpose: 
-- 1. Fix 'operator does not exist: uuid = text' error by casting.
-- 2. Ensure Admins can UPDATE cases (Assign/Approve).
-- ============================================================================

-- 1. Drop potentially broken policies
DROP POLICY IF EXISTS "Admins can update all cases" ON cases;
DROP POLICY IF EXISTS "Organizations can update assigned cases" ON cases;

-- 2. Create permissive policy for Admins (with explicit casting)
-- We check public.users.role for the current user.
CREATE POLICY "Admins can update all cases"
ON cases FOR UPDATE
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
)
WITH CHECK (
  (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
);

-- 3. Create policy for Organization users
-- CAST both sides to text to be safe against schema mismatches
CREATE POLICY "Organizations can update assigned cases"
ON cases FOR UPDATE
TO authenticated
USING (
  assigned_to = (SELECT organization_name FROM public.users WHERE id = auth.uid()) OR
  created_by::text = auth.uid()::text
)
WITH CHECK (
  assigned_to = (SELECT organization_name FROM public.users WHERE id = auth.uid()) OR
  created_by::text = auth.uid()::text
);

-- 4. Enable RLS
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- 5. Helper verification
DO $$
BEGIN
  RAISE NOTICE 'Fixed RLS policies with type casting.';
END $$;
