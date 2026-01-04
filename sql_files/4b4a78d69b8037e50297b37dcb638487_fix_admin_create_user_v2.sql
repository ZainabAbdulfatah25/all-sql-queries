­-- ============================================================================
-- FIX ADMIN CREATE USER (VERSION 2)
-- Purpose: Robust fix for "User Record Not Found".
--          Strictly ensures RLS policies allow the function to see the admin's own record.
-- ============================================================================

-- 1. Ensure RLS Policy is ABSOLUTELY correct for reading own profile
DROP POLICY IF EXISTS "Enable Read Access for Authenticated Users" ON users;
CREATE POLICY "Enable Read Access for Authenticated Users"
ON users FOR SELECT
TO authenticated
USING (
  auth.uid() = id
  OR
  -- Also allow reading if you are an admin (redundant but safe)
  (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
);

-- 2. Redefine the Function with better debugging/fallback
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
  v_org_id UUID;
  v_org_name TEXT;
  v_executor_id UUID;
BEGIN
  v_executor_id := auth.uid();
  
  -- Check if ID exists first (Debugging aid)
  -- We assume if this returns NULL, then RLS is blocking us or user truly doesn't exist.
  SELECT role, organization_id, organization_name 
  INTO v_current_user_role, v_org_id, v_org_name
  FROM users
  WHERE id = v_executor_id;

  IF v_current_user_role IS NULL THEN
      -- Use a slightly different error message to help debug if it persists
      RAISE EXCEPTION 'Access Denied: Could not verify your admin privileges. (User ID: %). This usually means RLS policies are blocking access to your own user record.', v_executor_id;
  END IF;

  -- Logic
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') THEN
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;

  ELSIF v_current_user_role IN ('organization', 'manager') THEN 
    IF p_role IN ('admin', 'super_admin', 'state_admin') THEN
        RAISE EXCEPTION 'Unauthorized: Organizations cannot create Admin users.';
    END IF;
    
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_org_name, p_organization_type, v_org_id)
    RETURNING * INTO v_new_user;
    RETURN v_new_user;

  ELSE
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create users.', v_current_user_role;
  END IF;
END;
$$;
­*cascade08"(fd95c6f46cc341b8b9b56abb9db74265d80b74a62;file:///home/zainab/Restore360/fix_admin_create_user_v2.sql:file:///home/zainab/Restore360