-- ============================================================================
-- FIX CASE RLS CASTING & PERMISSIONS (V2 - AGGRESSIVE CLEANUP)
-- Purpose: 
-- 1. Drop ALL existing policies on 'cases' to remove any hidden broken rules.
-- 2. Recreate policies with EXPLICIT casting to avoid 'uuid = text' errors.
-- ============================================================================

-- 1. Drop ALL potential policies (Aggressive cleanup)
DROP POLICY IF EXISTS "Admins can update all cases" ON cases;
DROP POLICY IF EXISTS "Organizations can update assigned cases" ON cases;
DROP POLICY IF EXISTS "Enable read access for all users" ON cases;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON cases;
DROP POLICY IF EXISTS "Users can view their own cases" ON cases;
DROP POLICY IF EXISTS "Admins can view all cases" ON cases;
DROP POLICY IF EXISTS "Organizations can view assigned cases" ON cases;
DROP POLICY IF EXISTS "Anyone can create cases" ON cases;

-- 2. Enable RLS
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;

-- 3. Create READ Policy (Select)
-- Admins: All
-- Users: Created by self OR Assigned to their Org
CREATE POLICY "Unified Read Policy"
ON cases FOR SELECT
TO authenticated
USING (
  -- Admin Check
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Creator Check
  created_by::text = auth.uid()::text
  OR
  -- Assignment Check
  assigned_to = (SELECT organization_name FROM public.users WHERE id::text = auth.uid()::text)
);

-- 4. Create INSERT Policy
-- Any authenticated user can create a case
CREATE POLICY "Unified Insert Policy"
ON cases FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
);

-- 5. Create UPDATE Policy
-- Admins: All
-- Users: Assigned to their Org OR Created by self
CREATE POLICY "Unified Update Policy"
ON cases FOR UPDATE
TO authenticated
USING (
  -- Admin Check
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Creator Check
  created_by::text = auth.uid()::text
  OR
  -- Assignment Check
  assigned_to = (SELECT organization_name FROM public.users WHERE id::text = auth.uid()::text)
)
WITH CHECK (
  -- Admin Check
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Creator Check
  created_by::text = auth.uid()::text
  OR
  -- Assignment Check
  assigned_to = (SELECT organization_name FROM public.users WHERE id::text = auth.uid()::text)
);

-- 6. Create DELETE Policy
-- Only Admins
CREATE POLICY "Unified Delete Policy"
ON cases FOR DELETE
TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
);

DO $$
BEGIN
  RAISE NOTICE 'Aggressively scrubbed and recreated Case RLS policies with strict casting.';
END $$;
