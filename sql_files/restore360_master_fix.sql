-- MASTER FIX SCRIPT for Restore360
-- Runs all critical fixes in one go.

BEGIN;

-- 1. Fix Admin Create User Function (Allows Org Admins to create Staff)
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
BEGIN
  -- Get current user's role
  SELECT role INTO v_current_user_role
  FROM users
  WHERE id = auth.uid();

  -- Check permissions
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;
  ELSIF v_current_user_role IN ('organization', 'manager') AND p_role != 'admin' THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;
  ELSE
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create a "%" user.', v_current_user_role, p_role;
  END IF;
END;
$$;

-- 2. Fix Users List Visibility
CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role TEXT;
  v_org_id UUID;
BEGIN
  SELECT role, organization_id INTO v_user_role, v_org_id
  FROM users
  WHERE id = auth.uid();

  IF v_user_role IN ('admin', 'state_admin', 'super_admin') THEN
     RETURN QUERY SELECT * FROM users;
  ELSIF v_user_role IN ('organization', 'manager') THEN
     RETURN QUERY SELECT * FROM users WHERE organization_id = v_org_id OR id = auth.uid();
  ELSE
     RAISE EXCEPTION 'Unauthorized: You do not have permission to view users list.';
  END IF;
END;
$$;

-- 3. Fix Referrals RLS
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated_can_create_referrals" ON referrals;
CREATE POLICY "authenticated_can_create_referrals" ON referrals FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "users_can_view_referrals" ON referrals;
CREATE POLICY "users_can_view_referrals" ON referrals FOR SELECT TO authenticated USING (true); 
-- (Simplified visibility for compatibility, can be tightened later)

DROP POLICY IF EXISTS "users_can_update_referrals" ON referrals;
CREATE POLICY "users_can_update_referrals" ON referrals FOR UPDATE TO authenticated USING (true);

-- 4. Fix Cases RLS
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated_can_create_cases" ON cases;
CREATE POLICY "authenticated_can_create_cases" ON cases FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "users_can_view_cases" ON cases;
CREATE POLICY "users_can_view_cases" ON cases FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "users_can_update_cases" ON cases;
CREATE POLICY "users_can_update_cases" ON cases FOR UPDATE TO authenticated USING (true);


COMMIT;
