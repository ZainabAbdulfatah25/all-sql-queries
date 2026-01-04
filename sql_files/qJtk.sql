-- PostgreSQL migration for Supabase
-- Fix Infinite Recursion in Users RLS Policies

-- Drop existing policies
DROP POLICY IF EXISTS users_can_view_based_on_role ON users;
DROP POLICY IF EXISTS authorized_users_can_create_new_users ON users;
DROP POLICY IF EXISTS users_can_update_based_on_role ON users;
DROP POLICY IF EXISTS only_admins_can_delete_users ON users;

-- Create new policies
CREATE POLICY users_can_view_own_profile ON users
FOR SELECT TO authenticated
USING (id = auth.uid());

CREATE POLICY users_can_create_own_profile ON users
FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

CREATE POLICY users_can_update_own_profile ON users
FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Helper functions
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND role = 'admin'
  );
END;
$$;

CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'Unauthorized: Only admins can view all users';
  END IF;
  RETURN QUERY SELECT * FROM users;
END;
$$;

CREATE OR REPLACE FUNCTION admin_create_user(
  p_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_organization_name TEXT DEFAULT NULL,
  p_organization_type TEXT DEFAULT NULL
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
  SELECT role INTO v_current_user_role
  FROM users
  WHERE id = auth.uid();

  IF v_current_user_role = 'admin' THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;
  ELSIF v_current_user_role = 'organization' AND p_role != 'admin' THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;
  ELSE
    RAISE EXCEPTION 'Unauthorized: Insufficient permissions to create user with role %', p_role;
  END IF;
END;
$$;