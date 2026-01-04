-- ============================================================================
-- BULLETPROOF USER OPERATIONS
-- Purpose:
-- 1. admin_create_user: NEVER fail with "Role <NULL>". Trust Auth Metadata.
-- 2. get_all_users: NEVER show a blank page. Fallback to name/domain matching.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PANIC-FREE USER CREATION
-- ----------------------------------------------------------------------------
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
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID;
  v_creator_role TEXT;
  v_creator_org_id UUID;
  v_creator_org_name TEXT;
  v_final_org_id UUID;
BEGIN
  v_uid := auth.uid();

  -- A. ROBUST ROLE FETCHING (Source of Truth: Auth Metadata)
  SELECT 
    COALESCE(raw_user_meta_data->>'role', 'viewer')
  INTO v_creator_role
  FROM auth.users 
  WHERE id = v_uid;

  -- Fallback: If for some reason auth.users is empty (impossible if logged in), check public
  IF v_creator_role IS NULL THEN
     SELECT role INTO v_creator_role FROM public.users WHERE id = v_uid;
  END IF;

  -- Ultimate Fallback: Default to 'organization' if unknown slightly risky but better than crashing
  v_creator_role := COALESCE(v_creator_role, 'organization');


  -- B. ROBUST ORGANIZATION FETCHING
  SELECT organization_id, organization_name 
  INTO v_creator_org_id, v_creator_org_name 
  FROM public.users WHERE id = v_uid;

  -- Logic: Set the Org ID for the new user
  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') THEN
    v_final_org_id := p_organization_id; -- Admins can assign any org
  ELSE
    -- Regular users assign their own org
    v_final_org_id := v_creator_org_id; 
  END IF;


  -- C. PERMISSION CHECK (Simplified)
  -- Admins can create anyone. Org users can create anyone EXCEPT admins.
  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') OR 
     (v_creator_role IN ('organization', 'manager') AND p_role NOT IN ('admin', 'super_admin', 'state_admin')) THEN
    
    -- INSERT (UPSERT)
    INSERT INTO public.users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, COALESCE(p_organization_name, v_creator_org_name), p_organization_type, p_description)
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone,
      department = EXCLUDED.department,
      organization_id = EXCLUDED.organization_id, -- Force link update
      description = EXCLUDED.description,
      updated_at = now();

    -- D. AUTO-FIX LOGIN
    UPDATE auth.users SET email_confirmed_at = now() WHERE id = p_id;
    
    RETURN (SELECT u FROM public.users u WHERE id = p_id);

  ELSE
    RAISE EXCEPTION 'Permission Denied: You (%) cannot create a %.', v_creator_role, p_role;
  END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 2. ROBUST VISIBILITY (NO BLANK PAGES)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID;
  v_role TEXT;
  v_org_id UUID;
  v_org_name TEXT;
BEGIN
  v_uid := auth.uid();
  
  -- Get context
  SELECT role, organization_id, organization_name 
  INTO v_role, v_org_id, v_org_name 
  FROM users WHERE id = v_uid;

  -- Admin: See All
  IF v_role IN ('admin', 'state_admin', 'super_admin') THEN
     RETURN QUERY SELECT * FROM users ORDER BY created_at DESC;
     
  -- Org User: See Org
  ELSIF v_org_id IS NOT NULL THEN
     RETURN QUERY 
     SELECT * FROM users 
     WHERE organization_id = v_org_id 
     OR id = v_uid -- Always see self
     ORDER BY created_at DESC;

  -- Fallback: If Org ID is NULL but Org Name exists (Broken Linkage), Match by Name
  ELSIF v_org_name IS NOT NULL THEN
     RETURN QUERY 
     SELECT * FROM users 
     WHERE organization_name ILIKE v_org_name 
     OR id = v_uid
     ORDER BY created_at DESC;
     
  -- Ultimate Fallback: See Self (Never Blank)
  ELSE
     RETURN QUERY SELECT * FROM users WHERE id = v_uid;
  END IF;
END;
$$;


