-- ============================================================================
-- SYNC AND FIX PERMISSIONS
-- Purpose: 
-- 1. Ensure all Auth users have a Public profile (Fixes "Role <NULL>" if row missing).
-- 2. Force-update the current user's role to 'organization' to ensure they have access.
-- 3. Update admin_create_user to show the User ID in errors for debugging.
-- ============================================================================

-- 1. Sync missing users from auth.users to public.users
INSERT INTO public.users (id, email, name, role, created_at, updated_at)
SELECT 
    id, 
    email, 
    COALESCE(raw_user_meta_data->>'name', email) as name,
    COALESCE(raw_user_meta_data->>'role', 'ordinary_user') as role,
    created_at,
    now()
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.users)
ON CONFLICT (id) DO NOTHING;

-- 2. Force Update Role for your specific email (to guarantee permission)
UPDATE public.users 
SET role = 'organization' 
WHERE email = 'abdulfatahzainab3@gmail.com';

-- 3. Update admin_create_user with BETTER ERROR MESSAGES
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
  p_description TEXT DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth -- Include auth schema
AS $$
DECLARE
  v_current_user_role TEXT;
  v_new_user users;
  v_uid UUID;
BEGIN
  v_uid := auth.uid();

  -- Get current user's role
  SELECT role INTO v_current_user_role
  FROM users
  WHERE id = v_uid;

  -- Default role to 'viewer' if null, to avoid "NULL" error confusion, 
  -- OR keep it null but log the ID in the error.
  
  -- Check permissions (Admins, or Org Managers creating non-admins)
  IF v_current_user_role IN ('admin', 'super_admin', 'state_admin') OR 
     (v_current_user_role IN ('organization', 'manager') AND p_role != 'admin') THEN
    
    INSERT INTO users (id, email, name, role, phone, department, organization_name, organization_type, organization_id, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, p_organization_name, p_organization_type, p_organization_id, p_description)
    ON CONFLICT (id) DO UPDATE
    SET 
      email = EXCLUDED.email,
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone,
      department = EXCLUDED.department,
      organization_name = EXCLUDED.organization_name,
      organization_type = EXCLUDED.organization_type,
      organization_id = EXCLUDED.organization_id,
      description = EXCLUDED.description,
      updated_at = now()
    RETURNING * INTO v_new_user;
    
    RETURN v_new_user;
    
  ELSE
    -- Improved Error Message
    RAISE EXCEPTION 'Unauthorized: User % (Role %) does not have permission to create a "%" user.', v_uid, COALESCE(v_current_user_role, '<NULL>'), p_role;
  END IF;
END;
$$;
