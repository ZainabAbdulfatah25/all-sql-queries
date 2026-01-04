-- ============================================================================
-- EMERGENCY PRIVACY RESET
-- Purpose: 
-- 1. Drop ALL potentially conflicting RLS policies (Ghost Policies).
-- 2. Re-apply Strict, Real-Time RLS.
-- 3. Force Unlink 'zainabsani'.
-- ============================================================================

-- A. CLEAN SLATE (Drop anything that might allow access)
-- Note: Postgres allows dropping non-existent policies without error if 'IF EXISTS' is used.
DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;
DROP POLICY IF EXISTS "Beneficiaries Select" ON registrations;
DROP POLICY IF EXISTS "Enable read access for all users" ON registrations;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON registrations;
DROP POLICY IF EXISTS "Allow authenticated read" ON registrations;
DROP POLICY IF EXISTS "Public View" ON registrations;
DROP POLICY IF EXISTS "view_all_registrations" ON registrations;
DROP POLICY IF EXISTS "select_own_registrations" ON registrations;

-- Also clean Household Members
DROP POLICY IF EXISTS "Household Members Visibility" ON household_members;
DROP POLICY IF EXISTS "Enable read access for all users" ON household_members;
DROP POLICY IF EXISTS "view_all_members" ON household_members;


-- B. APPLY STRICT POLICY (The Only One Allowed)
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- 1. ADMINS (Global)
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATIONS (Real-Time Check)
  (
    -- Must have Org Role AND Live Org ID in DB
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
       SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
       AND u.organization_id IS NOT NULL
       -- Matches the record's creator's org
       AND u.organization_id = (SELECT c.organization_id FROM users c WHERE c.id = registrations.created_by)
    )
  )

  OR

  -- 3. INDIVIDUALS / EVERYONE (Fallback: Own Only)
  (
     created_by = auth.uid()
  )
);

-- Re-apply Insert/Update/Delete Guards
DROP POLICY IF EXISTS "Beneficiaries Insert" ON registrations;
CREATE POLICY "Beneficiaries Insert"
ON registrations FOR INSERT TO authenticated
WITH CHECK ( created_by = auth.uid() );

DROP POLICY IF EXISTS "Beneficiaries Update" ON registrations;
CREATE POLICY "Beneficiaries Update"
ON registrations FOR UPDATE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin') OR
  created_by = auth.uid() OR
  (get_auth_user_role() IN ('organization', 'manager') AND get_auth_user_org_id() IS NOT NULL)
);

DROP POLICY IF EXISTS "Beneficiaries Delete" ON registrations;
CREATE POLICY "Beneficiaries Delete"
ON registrations FOR DELETE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin') OR
  created_by = auth.uid()
);


-- C. FIX ZAINAB SANI (Again, forcefully)
DO $$
BEGIN
  -- Unlink
  UPDATE public.users 
  SET organization_id = NULL, organization_name = NULL, role = 'case_worker'
  WHERE email = 'zainabsani@example.com';

  -- Sync Metadata
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_build_object('role', 'case_worker', 'organization_id', NULL)
  WHERE email = 'zainabsani@example.com';
END $$;
