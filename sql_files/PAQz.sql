-- ============================================================================
-- SYSTEM-WIDE ORGANIZATION FIX
-- Purpose: 
-- 1. Ensure EVERY 'organization_name' in the users table has a real Organization ID.
-- 2. Link all users to these IDs so visibility works for EVERYONE.
-- 3. Grant permissions for Org Admins to UPDATE their staff.
-- ============================================================================

DO $$
BEGIN

  -- 1. Auto-Create missing Organizations found in User profiles
  --    If a user has "Red Cross" but it's not in the organizations table, create it.
  INSERT INTO organizations (name, organization_name, type, is_active)
  SELECT DISTINCT u.organization_name, u.organization_name, 'NGO', true
  FROM users u
  WHERE u.organization_name IS NOT NULL 
    AND u.organization_name != ''
    AND NOT EXISTS (
      SELECT 1 FROM organizations o WHERE o.name = u.organization_name OR o.organization_name = u.organization_name
    );

  RAISE NOTICE 'Step 1: Created missing organizations from user data.';

  -- 2. Backfill organization_id for ALL users
  --    This connects the "String Name" to the "Real ID" for everyone.
  UPDATE users u
  SET organization_id = o.id
  FROM organizations o
  WHERE (u.organization_name = o.name OR u.organization_name = o.organization_name)
    AND u.organization_id IS NULL;

  RAISE NOTICE 'Step 2: Linked users to their organization IDs.';

  -- 3. Safety: If any user has an ID but no Name (rare), fill the Name
  UPDATE users u
  SET organization_name = o.name
  FROM organizations o
  WHERE u.organization_id = o.id
    AND (u.organization_name IS NULL OR u.organization_name = '');

END $$;


-- 4. PERMISSIONS: Allow Org Admins to UPDATE their staff
--    (Dropping old policies first to be clean)
DROP POLICY IF EXISTS "Org Admins can update their staff" ON users;
DROP POLICY IF EXISTS "Organization members can view their own organization members" ON users;

-- Re-apply robust RLS for UPDATING
CREATE POLICY "Org Admins can update their staff"
ON users
FOR UPDATE
TO authenticated
USING (
  (SELECT role FROM users WHERE id = auth.uid()) IN ('organization', 'manager') 
  AND 
  organization_id = (SELECT organization_id FROM users WHERE id = auth.uid())
);

-- Re-apply robust RLS for SELECT (Visibility) - though RPC handles most lists, this helps with single item fetches
CREATE POLICY "Org members can view their colleagues"
ON users
FOR SELECT
TO authenticated
USING (
  -- Admins see all
  (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Users see themselves
  id = auth.uid()
  OR
  -- Users see others in same org
  organization_id = (SELECT organization_id FROM users WHERE id = auth.uid())
);

RAISE NOTICE 'Step 4: Updated RLS policies for View and Update.';
