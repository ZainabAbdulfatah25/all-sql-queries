-- ============================================================================
-- FIX ORGANIZATION CREATION PERMISSIONS
-- Purpose: Allow Admins to create new organizations via the Dashboard.
--          (Enforce strict RLS on 'organizations' table)
-- ============================================================================

-- 1. Enable RLS
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies to ensure a clean slate
-- (Dynamic drop to catch any old policy names)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'organizations' AND schemaname = 'public') LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.organizations';
    RAISE NOTICE 'Dropped old policy: %', r.policyname;
  END LOOP;
END $$;

-- 3. Create Unified Policies

-- READ: Everyone (Authenticated) needs to read organizations to populate dropdowns/directories
CREATE POLICY "Unified Org Read Policy" ON public.organizations
FOR SELECT TO authenticated
USING (true);

-- INSERT: Only Admins (Global) can create new organizations
-- (Regular users or Org Admins cannot create NEW organizations, typically)
CREATE POLICY "Unified Org Insert Policy" ON public.organizations
FOR INSERT TO authenticated
WITH CHECK (
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
);

-- UPDATE: 
-- 1. Global Admins (can update any org)
-- 2. Org Admins (can update THEIR OWN org)
CREATE POLICY "Unified Org Update Policy" ON public.organizations
FOR UPDATE TO authenticated
USING (
  -- Global Admin
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Org Admin updating own org
  (
    get_auth_role() IN ('organization', 'manager') 
    AND 
    id = get_auth_org_id()
  )
)
WITH CHECK (
  -- Re-check condition
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
  OR
  (
    get_auth_role() IN ('organization', 'manager') 
    AND 
    id = get_auth_org_id()
  )
);

-- DELETE: Only Global Admins
CREATE POLICY "Unified Org Delete Policy" ON public.organizations
FOR DELETE TO authenticated
USING (
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
);

DO $$
BEGIN
  RAISE NOTICE 'Organization RLS policies fixed. Admins can now create organizations.';
END $$;
