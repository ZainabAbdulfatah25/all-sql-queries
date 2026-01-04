-- Update admin_create_user to support organization_id and manager role with IMPROVED DEBUGGING
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

  -- DEBUG: If role is null, the user record might be missing
  IF v_current_user_role IS NULL THEN
      RAISE EXCEPTION 'User Record Not Found for ID %. Your account might not be fully linked. Please contact support.', auth.uid();
  END IF;

  -- Check permissions
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') THEN
    -- Admins can create any user
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    
    RETURN v_new_user;
  ELSIF v_current_user_role IN ('organization', 'manager') AND p_role != 'admin' THEN
    -- Organizations/Managers can create non-admin users
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    
    RETURN v_new_user;
  ELSE
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create a "%" user.', v_current_user_role, p_role;
  END IF;
END;
$$;
