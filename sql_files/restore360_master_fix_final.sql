/*
  RESTORE360 MASTER FIX (FINAL)
  
  This script consolidates all fixes for RLS, Permissions, and Data Visibility.
  run this script to reset and fix the security layer of the application.
  
  COVERAGE:
  - Helper Functions (Safe Role/Org Access)
  - Users Table RLS
  - Registrations Table RLS
  - Cases Table RLS
  - Referrals Table RLS
  - User Creation Function (admin_create_user)
  - Data Fixes (Defensera / Missing Org Links)
*/

-- ============================================================================
-- 0. CLEANUP & PREP
-- ============================================================================

-- Drop potentially conflicting separate policy scripts if they were running partially
-- (We will replace policies by name, so this is just being thorough)

-- ============================================================================
-- 1. HELPER FUNCTIONS (SECURITY DEFINER)
--    These allow us to check roles/orgs inside RLS without recursion.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_auth_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (SELECT role FROM users WHERE id = auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION get_auth_org_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (SELECT organization_id FROM users WHERE id = auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION get_auth_role TO authenticated;
GRANT EXECUTE ON FUNCTION get_auth_org_id TO authenticated;

-- ============================================================================
-- 2. USERS TABLE RLS
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Organization admins can view their own organization users" ON users;
DROP POLICY IF EXISTS "Admins can view all users" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;

-- VIEW: Self, Global Admins, or Organization Admins viewing their staff
CREATE POLICY "Unified Users View Policy"
ON users FOR SELECT
TO authenticated
USING (
  -- 1. Self
  auth.uid() = id
  OR
  -- 2. Global Admins
  get_auth_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- 3. Organization Admins/Managers (Same Org)
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    organization_id = get_auth_org_id()
    AND
    organization_id IS NOT NULL
  )
);

-- UPDATE: Self, Global Admins, or Organization Admins updating their staff
CREATE POLICY "Unified Users Update Policy"
ON users FOR UPDATE
TO authenticated
USING (
  auth.uid() = id
  OR
  get_auth_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    organization_id = get_auth_org_id()
    AND
    organization_id IS NOT NULL
  )
);

-- INSERT: Open for signup (authenticated can create) - Validation handled by App/Functions
CREATE POLICY "Users can create users"
ON users FOR INSERT
TO authenticated
WITH CHECK (true);

-- DELETE: Admins or Org Admins (their staff)
CREATE POLICY "Unified Users Delete Policy"
ON users FOR DELETE
TO authenticated
USING (
  get_auth_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    organization_id = get_auth_org_id()
    AND
    organization_id IS NOT NULL
    AND
    id != auth.uid() -- Prevent self-delete if needed, or allow it.
  )
);

-- ============================================================================
-- 3. REGISTRATIONS TABLE RLS
--    Note: Table has no organization_id, so we link via created_by user.
-- ============================================================================

ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can insert registrations" ON registrations;
DROP POLICY IF EXISTS "Users can view own or org registrations" ON registrations;
DROP POLICY IF EXISTS "Users can update own or org registrations" ON registrations;

-- INSERT
CREATE POLICY "Users can create registrations"
ON registrations FOR INSERT
TO authenticated
WITH CHECK (true);

-- SELECT
CREATE POLICY "Unified Registrations View Policy"
ON registrations FOR SELECT
TO authenticated
USING (
  -- 1. Creator
  auth.uid() = created_by
  OR
  -- 2. Global Admin
  get_auth_role() IN ('admin', 'state_admin')
  OR
  -- 3. Org Admin (If Creator belongs to same Org)
  EXISTS (
    SELECT 1 FROM users creator
    WHERE creator.id = registrations.created_by
    AND creator.organization_id = get_auth_org_id()
    AND get_auth_org_id() IS NOT NULL
    AND get_auth_role() IN ('organization', 'manager')
  )
);

-- UPDATE
CREATE POLICY "Unified Registrations Update Policy"
ON registrations FOR UPDATE
TO authenticated
USING (
  auth.uid() = created_by
  OR
  get_auth_role() IN ('admin', 'state_admin')
  OR
  EXISTS (
    SELECT 1 FROM users creator
    WHERE creator.id = registrations.created_by
    AND creator.organization_id = get_auth_org_id()
    AND get_auth_org_id() IS NOT NULL
    AND get_auth_role() IN ('organization', 'manager')
  )
);

-- DELETE (Admins & Owners)
CREATE POLICY "Unified Registrations Delete Policy"
ON registrations FOR DELETE
TO authenticated
USING (
  auth.uid() = created_by
  OR
  get_auth_role() IN ('admin', 'state_admin')
  OR
  EXISTS (
    SELECT 1 FROM users creator
    WHERE creator.id = registrations.created_by
    AND creator.organization_id = get_auth_org_id()
    AND get_auth_org_id() IS NOT NULL
    AND get_auth_role() IN ('organization', 'manager')
  )
);

-- ============================================================================
-- 4. CASES TABLE RLS
--    Similar to Registrations (via created_by or assigned_to)
-- ============================================================================

ALTER TABLE cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view all cases" ON cases;
DROP POLICY IF EXISTS "Unified Cases View Policy" ON cases;

-- SELECT
CREATE POLICY "Unified Cases View Policy"
ON cases FOR SELECT
TO authenticated
USING (
  -- 1. Creator or Assignee
  auth.uid() = created_by
  OR
  auth.uid() = assigned_to
  OR
  -- 2. Global Admin
  get_auth_role() IN ('admin', 'state_admin')
  OR
  -- 3. Org Admin (If Creator OR Assignee belongs to same Org)
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    get_auth_org_id() IS NOT NULL
    AND
    (
       EXISTS (
         SELECT 1 FROM users u
         WHERE (u.id = cases.created_by OR u.id = cases.assigned_to)
         AND u.organization_id = get_auth_org_id()
       )
    )
  )
);

-- INSERT
CREATE POLICY "Users can create cases"
ON cases FOR INSERT
TO authenticated
WITH CHECK (true);

-- UPDATE
CREATE POLICY "Unified Cases Update Policy"
ON cases FOR UPDATE
TO authenticated
USING (
  auth.uid() = created_by
  OR
  auth.uid() = assigned_to
  OR
  get_auth_role() IN ('admin', 'state_admin')
  OR
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    get_auth_org_id() IS NOT NULL
    AND
    (
       EXISTS (
         SELECT 1 FROM users u
         WHERE (u.id = cases.created_by OR u.id = cases.assigned_to)
         AND u.organization_id = get_auth_org_id()
       )
    )
  )
);

-- ============================================================================
-- 5. REFERRALS TABLE RLS
--    Has assigned_organization_id
-- ============================================================================

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view all referrals" ON referrals;
DROP POLICY IF EXISTS "Unified Referrals View Policy" ON referrals;

-- SELECT
CREATE POLICY "Unified Referrals View Policy"
ON referrals FOR SELECT
TO authenticated
USING (
  -- 1. Creator
  auth.uid() = created_by
  OR
  -- 2. Assigned to My Organization
  assigned_organization_id = get_auth_org_id()
  OR
  -- 3. Global Admin
  get_auth_role() IN ('admin', 'state_admin')
);

-- INSERT
CREATE POLICY "Users can create referrals"
ON referrals FOR INSERT
TO authenticated
WITH CHECK (true);

-- UPDATE
CREATE POLICY "Unified Referrals Update Policy"
ON referrals FOR UPDATE
TO authenticated
USING (
  auth.uid() = created_by
  OR
  assigned_organization_id = get_auth_org_id()
  OR
  get_auth_role() IN ('admin', 'state_admin')
);

-- ============================================================================
-- 6. ADMIN CREATE USER FUNCTION FIX
-- ============================================================================

CREATE OR REPLACE FUNCTION admin_create_user(
  p_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_organization_name TEXT DEFAULT NULL,
  p_organization_type TEXT DEFAULT NULL,
  p_organization_id UUID DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_role TEXT;
  v_new_user users;
  v_org_id UUID;
  v_org_name TEXT;
BEGIN
  -- Get current user's role
  SELECT role INTO v_current_user_role
  FROM users
  WHERE id = auth.uid();

  IF v_current_user_role IS NULL THEN
      RAISE EXCEPTION 'User Record Not Found for ID %. Please contact support.', auth.uid();
  END IF;

  -- Logic
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') THEN
    -- Admins can create any user
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    
    RETURN v_new_user;

  ELSIF v_current_user_role IN ('organization', 'manager') THEN 
    -- Org Admins can create non-admin users (case_worker, field_worker, etc)
    -- BUT NOT other admins or organization roles that might escalate privilege
    -- (Allowing 'manager', 'case_worker', 'field_worker', 'organization' is fine for this context)
    
    IF p_role IN ('admin', 'super_admin', 'state_admin') THEN
        RAISE EXCEPTION 'Unauthorized: Organizations cannot create Admin users.';
    END IF;

    -- FORCE organization assignment
    SELECT organization_id, organization_name INTO v_org_id, v_org_name
    FROM users
    WHERE id = auth.uid();
      
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_org_name, p_organization_type, v_org_id)
    RETURNING * INTO v_new_user;
      
    RETURN v_new_user;

  ELSE
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create users.', v_current_user_role;
  END IF;
END;
$$;

-- ============================================================================
-- 7. DATA FIX (DEFENSERA)
--    Ensures the user who ran into issues is fixed.
-- ============================================================================

DO $$
DECLARE
  v_org_id UUID;
  v_user_email TEXT := 'defensera@example.com'; 
BEGIN
  -- Find Org
  SELECT id INTO v_org_id 
  FROM organizations 
  WHERE organization_name ILIKE 'Defensera' OR name ILIKE 'Defensera'
  LIMIT 1;

  IF v_org_id IS NOT NULL THEN
      -- Link Users with that email pattern or explicitly
      UPDATE users 
      SET organization_id = v_org_id, role = 'organization'
      WHERE email ILIKE v_user_email AND organization_id IS NULL;
  END IF;
END $$;

