-- ============================================================================
-- FIX USER CREATION CONFLICTS & LOGIN ISSUES
-- Purpose: 
-- 1. Handle "Duplicate Key" errors if a trigger already created the user row.
-- 2. Auto-confirm users so they can login immediately (Fixes "Invalid login credentials").
-- ============================================================================

-- 1. Update admin_create_user to use UPSERT (Insert or Update)
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
    RAISE EXCEPTION 'Unauthorized: Your Role "%" does not have permission to create a "%" user.', v_current_user_role, p_role;
  END IF;
END;
$$;


-- 2. Auto-Confirm Existing Users (Fixes current "Invalid login credentials")
-- Requires privileges on auth.users (Supabase SQL Editor has this)
UPDATE auth.users
SET email_confirmed_at = now()
WHERE email_confirmed_at IS NULL;


-- 3. (Optional) Create Trigger to Auto-Confirm Future Users
-- This ensures any new user created via SignUp is immediately valid.
CREATE OR REPLACE FUNCTION public.auto_confirm_user()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE auth.users
  SET email_confirmed_at = now()
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on public.users (Assuming public.users is populated after auth.users)
-- Actually, we can't easily trigger on auth.users from here without superuser.
-- Helper: Just run the UPDATE above periodically if issues persist, 
-- or rely on the fact that we are manually confirming for now.
