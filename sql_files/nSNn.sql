/*
  # Fixed Users RLS Policies & Admin/Organization Functions
  - Prevent infinite recursion in RLS
  - Allow admins full access
  - Allow organization users to manage non-admin users
*/

-- ============================================================================
-- DROP EXISTING POLICIES
-- ============================================================================

DROP POLICY IF EXISTS users_can_view_based_on_role ON users;
DROP POLICY IF EXISTS authorized_users_can_create_new_users ON users;
DROP POLICY IF EXISTS users_can_update_based_on_role ON users;
DROP POLICY IF EXISTS only_admins_can_delete_users ON users;

-- ============================================================================
-- CREATE NEW RLS POLICIES
-- ============================================================================

-- Users can view their own profile
CREATE POLICY users_can_view_own_profile
ON users FOR SELECT
TO authenticated
USING (id = auth.uid());

-- Users can create their own profile
CREATE POLICY users_can_create_own_profile
ON users FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

-- Users can update their own profile
CREATE POLICY users_can_update_own_profile
ON users FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- DELETE: None, must use admin functions

-- ============================================================================
-- HELPER FUNCTIONS FOR ROLE CHECKS
-- ============================================================================

-- Check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
      AND role = 'admin'
  );
END;
$$;

-- Check if current user is organization
CREATE OR REPLACE FUNCTION is_organization()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
      AND role = 'organization'
  );
END;
$$;

-- ============================================================================
-- FUNCTIONS FOR ADMIN / ORGANIZATION OPERATIONS
-- ============================================================================

-- Get all users (admin only)
CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Unauthorized: Only admins can view all users';
  END IF;

  RETURN QUERY SELECT * FROM users;
END;
$$;

-- Create user (admin or organization)
CREATE OR REPLACE FUNCTION create_user_with_role(
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
AS $$
DECLARE
  v_new_user users;
BEGIN
  IF is_admin() THEN
    -- Admins can create any user
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type)
    RETURNING * INTO v_new_user;

  ELSIF is_organization() AND p_role != 'admin' THEN
    -- Organization can create non-admin users
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type)
    RETURNING * INTO v_new_user;

  ELSE
    RAISE EXCEPTION 'Unauthorized: Insufficient permissions to create user with role %', p_role;
  END IF;

  RETURN v_new_user;
END;
$$;

-- Update user (admin can update any, org can update non-admins)
CREATE OR REPLACE FUNCTION update_user_with_role(
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
AS $$
DECLARE
  v_target_role TEXT;
  v_updated_user users;
BEGIN
  -- Get target user's role
  SELECT role INTO v_target_role FROM users WHERE id = p_id;

  IF is_admin() THEN
    -- Admin can update any user
    UPDATE users
    SET email = p_email,
        name = p_name,
        role = p_role,
        phone = p_phone,
        department = p_department,
        organization_name = p_organization_name,
        organization_type = p_organization_type
    WHERE id = p_id
    RETURNING * INTO v_updated_user;

  ELSIF is_organization() AND v_target_role != 'admin' THEN
    -- Org can update non-admins
    UPDATE users
    SET email = p_email,
        name = p_name,
        role = p_role,
        phone = p_phone,
        department = p_department,
        organization_name = p_organization_name,
        organization_type = p_organization_type
    WHERE id = p_id
    RETURNING * INTO v_updated_user;

  ELSE
    RAISE EXCEPTION 'Unauthorized: Insufficient permissions to update this user';
  END IF;

  RETURN v_updated_user;
END;
$$;
