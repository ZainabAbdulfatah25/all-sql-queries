”-- ============================================================================
-- FIX ADMIN CREATE USER FUNCTION
-- Purpose: Resolve "User Record Not Found" by fixing how the function checks capabilities.
-- ============================================================================

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
SECURITY DEFINER -- Runs with owner permissions (usually Postgres/Admin) to bypass simple RLS
SET search_path = public
AS $$
DECLARE
  v_current_user_role TEXT;
  v_new_user users;
  v_org_id UUID;
  v_org_name TEXT;
  v_executor_id UUID;
BEGIN
  -- Get Executor ID safely
  v_executor_id := auth.uid();

  -- 1. Get current user's role securely
  -- We use a direct query. Since this is SECURITY DEFINER, it *should* see all data
  -- if the owner is superuser. If not, we might need to rely on RLS allowing it.
  -- We'll assume the unified policy exists. 
  SELECT role, organization_id, organization_name 
  INTO v_current_user_role, v_org_id, v_org_name
  FROM users
  WHERE id = v_executor_id;

  IF v_current_user_role IS NULL THEN
      -- Fallback: If RLS blocked the SELECT but we are effectively logged in, 
      -- we might be able to trust JWT claims (if accessible), or just fail with more info.
      -- Let's try to grab from auth.users metadata if possible (requires access to auth schema which is blocked usually).
      
      -- Instead, let's assume if we are here, we are authenticated. 
      -- If the SELECT failed, it means RLS is active and "Unified View Policy" didn't work for some reason.
      -- However, let's try to proceed by assuming we might be blocked.
      
      RAISE EXCEPTION 'User Record Not Found for ID %. Ensure RLS allows viewing your own profile.', v_executor_id;
  END IF;

  -- 2. Logic
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') THEN
    -- Admins can create any user
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id)
    RETURNING * INTO v_new_user;
    
    RETURN v_new_user;

  ELSIF v_current_user_role IN ('organization', 'manager') THEN 
    -- Org Admins can create non-admin users
    
    IF p_role IN ('admin', 'super_admin', 'state_admin') THEN
        RAISE EXCEPTION 'Unauthorized: Organizations cannot create Admin users.';
    END IF;

    -- Update Organization Info from the Executor's profile to ensure consistency
    -- (We ignore whatever was passed in p_organization_id if not null, to enforce same org)
    
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_org_name, p_organization_type, v_org_id)
    RETURNING * INTO v_new_user;
      
    RETURN v_new_user;

  ELSE
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create users.', v_current_user_role;
  END IF;
END;
$$;

-- ENSURE RLS IS CORRECT FOR SELF-VIEW (Just in case)
DROP POLICY IF EXISTS "Allow users to read own profile admin_fix" ON users;
CREATE POLICY "Allow users to read own profile admin_fix"
ON users FOR SELECT
TO authenticated
USING (
  auth.uid() = id
);
”"(7a194eb93e0aa50a7b36559f974074beeac640a528file:///home/zainab/Restore360/fix_admin_create_user.sql:file:///home/zainab/Restore360