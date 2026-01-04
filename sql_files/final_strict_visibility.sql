-- ============================================================================
-- FINAL STRICT VISIBILITY RULES
-- Purpose: 
-- 1. Enforce STRICT visibility for Activity Logs based on Role.
-- 2. Rules:
--    - Admin/State Admin: View ALL activities.
--    - Organization/Manager: View activities of users in THEIR organization.
--    - Individual User: View ONLY their own activities.
-- ============================================================================

-- 1. ENSURE HELPER FUNCTIONS EXIST & ARE SECURE
-- (Re-defining here to be absolutely safe they exist and work correctly)

CREATE OR REPLACE FUNCTION get_auth_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM users WHERE id = auth.uid();
  RETURN v_role;
END;
$$;

CREATE OR REPLACE FUNCTION get_auth_user_org_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id FROM users WHERE id = auth.uid();
  RETURN v_org_id;
END;
$$;


-- 2. APPLY STRICT RLS TO ACTIVITY LOGS
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Activity Logs Select" ON activity_logs;
DROP POLICY IF EXISTS "Activity Logs Insert" ON activity_logs;

-- A. SELECT POLICY (Visibility)
CREATE POLICY "Activity Logs Select"
ON activity_logs FOR SELECT TO authenticated
USING (
  -- 1. ADMINS: See Everything
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATIONS: See Their Org's Activity
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
       SELECT 1 FROM public.users u
       WHERE u.id = activity_logs.user_id
       AND u.organization_id = get_auth_user_org_id()
    )
  )

  OR

  -- 3. INDIVIDUALS: See Only Self
  (
     user_id = auth.uid()
  )
);

-- B. INSERT POLICY (Strictly Self)
CREATE POLICY "Activity Logs Insert"
ON activity_logs FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
);


-- 3. APPLY SIMILAR RULES TO USERS TABLE (As requested "Same as recent activity")
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable Read Access for Authenticated Users" ON users;

CREATE POLICY "Enable Read Access for Authenticated Users"
ON users FOR SELECT TO authenticated
USING (
  -- 1. ADMINS: See Everyone
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATIONS: See Their Org Members (and themselves)
  (
    organization_id = get_auth_user_org_id()
    OR 
    id = auth.uid()
  )

  OR

  -- 3. INDIVIDUALS: See Only Self
  (
     id = auth.uid()
  )
);

-- 4. VERIFY
DO $$
BEGIN
  RAISE NOTICE 'Strict Visibility Rules Applied: Admins(All), Orgs(Org), Users(Self).';
END $$;
