Ú-- ============================================================================
-- FIX USER UPDATE POLICY
-- Purpose: Explicitly allow Organization Admins/Managers to update their staff records.
--          (Including Role, Department, etc.)
-- ============================================================================

-- Drop existing policy to avoid conflicts/duplication
DROP POLICY IF EXISTS "Unified Users Update Policy" ON users;
DROP POLICY IF EXISTS "Organization Admins can update their organization users" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;

-- Create the robust Update Policy
CREATE POLICY "Unified Users Update Policy"
ON users FOR UPDATE
TO authenticated
USING (
  -- 1. Self (Can update own profile)
  auth.uid() = id
  OR
  -- 2. Global Admins (Can update anyone)
  get_auth_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- 3. Organization Admins (Can update staff in SAME organization)
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    organization_id = get_auth_org_id() -- User being updated must match my Org
    AND
    get_auth_org_id() IS NOT NULL
  )
)
WITH CHECK (
  -- 1. Self
  auth.uid() = id
  OR
  -- 2. Global Admins
  get_auth_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- 3. Organization Admins
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    organization_id = get_auth_org_id() -- Cannot move user to another Org
    AND
    get_auth_org_id() IS NOT NULL
  )
);
Ú*cascade08"(fd95c6f46cc341b8b9b56abb9db74265d80b74a629file:///home/zainab/Restore360/fix_user_update_policy.sql:file:///home/zainab/Restore360