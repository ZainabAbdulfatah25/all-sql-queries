»-- ============================================================================
-- UPDATE REGISTRATIONS RLS POLICY
-- Purpose: Allow ALL users within an organization to View and Update registrations.
--          (Previously limited to Organization Admins/Managers)
-- ============================================================================

-- 1. VIEW POLICY (SELECT)
DROP POLICY IF EXISTS "Unified Registrations View Policy" ON registrations;

CREATE POLICY "Unified Registrations View Policy"
ON registrations FOR SELECT
TO authenticated
USING (
  -- 1. Creator (Always allowed)
  auth.uid() = created_by
  OR
  -- 2. Global Admins (Always allowed)
  get_auth_role() IN ('admin', 'state_admin')
  OR
  -- 3. ANY User in the same Organization
  --    We check if the creator of the registration belongs to the same org as the current user.
  EXISTS (
    SELECT 1 FROM users creator
    WHERE creator.id = registrations.created_by
    AND creator.organization_id = get_auth_org_id()
    AND get_auth_org_id() IS NOT NULL
    -- REMOVED: AND get_auth_role() IN ('organization', 'manager') <-- This restriction is gone.
  )
);

-- 2. UPDATE POLICY (UPDATE)
DROP POLICY IF EXISTS "Unified Registrations Update Policy" ON registrations;

CREATE POLICY "Unified Registrations Update Policy"
ON registrations FOR UPDATE
TO authenticated
USING (
  -- 1. Creator
  auth.uid() = created_by
  OR
  -- 2. Global Admins
  get_auth_role() IN ('admin', 'state_admin')
  OR
  -- 3. ANY User in the same Organization
  EXISTS (
    SELECT 1 FROM users creator
    WHERE creator.id = registrations.created_by
    AND creator.organization_id = get_auth_org_id()
    AND get_auth_org_id() IS NOT NULL
    -- REMOVED: Role restriction
  )
);

-- Note: DELETE policy usually remains restricted to Admins/Managers/Creators, 
-- but if "all actors" implies delete too, we could change it. 
-- Usually "Update Status" is the key requirement. I will leave DELETE as is for safety unless requested.
»"(83ab2b8921e473966431d5887dca8ec59097a3d42>file:///home/zainab/Restore360/update_registrations_policy.sql:file:///home/zainab/Restore360