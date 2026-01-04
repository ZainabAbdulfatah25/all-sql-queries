-- ============================================================================
-- FIX BENEFICIARY PERMISSIONS (REGISTRATIONS RLS)
-- Purpose: Enforce tiered access control:
-- 1. Users: View/Manage Own.
-- 2. Organizations: View/Manage All in Org.
-- 3. Admins: View/Manage Everything.
-- ============================================================================

-- A. HELPER FUNCTIONS (Ensure they exist and are secure)
CREATE OR REPLACE FUNCTION get_auth_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN COALESCE(
    current_setting('request.jwt.claims', true)::jsonb->'user_metadata'->>'role',
    'viewer'
  );
END;
$$;

CREATE OR REPLACE FUNCTION get_auth_user_org_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id FROM users WHERE id = auth.uid();
  RETURN v_org_id;
END;
$$;


-- B. REGISTRATIONS TABLE
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;
DROP POLICY IF EXISTS "Beneficiaries Insert" ON registrations;
DROP POLICY IF EXISTS "Beneficiaries Update" ON registrations;
DROP POLICY IF EXISTS "Beneficiaries Delete" ON registrations;

-- 1. VIEW POLICY
CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- Admin: All
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- Owner: Theirs
  created_by = auth.uid()
  OR
  -- Org Admin: All in their Org
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )
);

-- 2. INSERT POLICY (Everyone can create, must own it)
CREATE POLICY "Beneficiaries Insert"
ON registrations FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
);

-- 3. UPDATE POLICY
CREATE POLICY "Beneficiaries Update"
ON registrations FOR UPDATE TO authenticated
USING (
  -- Admin: All
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- Owner: Theirs
  created_by = auth.uid()
  OR
  -- Org Admin: All in their Org
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )
);

-- 4. DELETE POLICY (Stricter: Only Admins or Owner?)
-- Let's allow Org Admin to delete too for management.
CREATE POLICY "Beneficiaries Delete"
ON registrations FOR DELETE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  created_by = auth.uid()
  OR
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )
);


-- C. HOUSEHOLD MEMBERS TABLE (Inherits from Registration)
ALTER TABLE household_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members Visibility" ON household_members;
DROP POLICY IF EXISTS "Members Modification" ON household_members;

-- 1. VIEW
CREATE POLICY "Members Visibility"
ON household_members FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM registrations r 
    WHERE r.id = household_members.registration_id
    -- Re-use the Registration Visibility Logic merely by selecting from it?
    -- No, RLS doesn't recurse nicely on subqueries if policies apply.
    -- Safest to explicit check logic OR assume if they can see registration (via policy) they can see member.
    -- Postgres RLS on subselects checks policies. So scanning 'registrations' checks its policies.
    -- So we just check if the ID exists in the visible registrations.
  )
);

-- 2. MODIFY (Insert/Update/Delete)
CREATE POLICY "Members Modification"
ON household_members FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM registrations r 
    WHERE r.id = household_members.registration_id
    AND (
      -- Check Update Permission logic explicitly or rely on Registration visibility + Role
       get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
       OR
       r.created_by = auth.uid()
       OR
       (
         get_auth_user_role() IN ('organization', 'manager') 
         AND 
         EXISTS (
            SELECT 1 FROM users creator 
            WHERE creator.id = r.created_by 
            AND creator.organization_id = get_auth_user_org_id()
         )
       )
    )
  )
);


