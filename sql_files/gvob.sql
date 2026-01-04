-- ============================================================================
-- ADD USER DESCRIPTION & UPDATE CREATION LOGIC
-- Purpose: Add 'description' column to users table and support it in admin_create_user.
-- ============================================================================

-- 1. Add description column
ALTER TABLE users ADD COLUMN IF NOT EXISTS description TEXT;

-- 2. Update admin_create_user function to accept description
CREATE OR REPLACE FUNCTION admin_create_user(
  p_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_organization_name TEXT DEFAULT NULL,
  p_organization_type TEXT DEFAULT NULL,
  p_organization_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL -- New Parameter
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
  -- Get current user's role (using the secure function if available, or direct query)
  SELECT role INTO v_current_user_role
  FROM users
  WHERE id = auth.uid();

  -- Check permissions
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id, p_description)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;
  ELSIF v_current_user_role IN ('organization', 'manager') AND p_role != 'admin' THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id, p_description)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;
  ELSE
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create a "%" user.', v_current_user_role, p_role;
  END IF;
END;
$$;
