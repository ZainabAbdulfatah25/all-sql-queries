-- Update get_all_users to allow Organization Admins to view their staff
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
  -- Get current user role and org id
  SELECT role, organization_id INTO v_user_role, v_org_id
  FROM users
  WHERE id = auth.uid();

  IF v_user_role IN ('admin', 'state_admin', 'super_admin') THEN
     RETURN QUERY SELECT * FROM users;
  ELSIF v_user_role IN ('organization', 'manager') THEN
     -- Only return users in their organization
     -- Also include the user themselves to be safe, though they are in the org
     RETURN QUERY SELECT * FROM users WHERE organization_id = v_org_id OR id = auth.uid();
  ELSE
     RAISE EXCEPTION 'Unauthorized: You do not have permission to view users list.';
  END IF;
END;
$$;
