-- ============================================================================
-- ALLOW UNIVERSAL USER CREATION
-- Purpose: 
-- 1. Remove strict role-based checks from 'admin_create_user'.
-- 2. Allow ANY authenticated user to create new users.
--    (Users will be created in the creator's organization).
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

  -- 1. GET CREATOR CONTEXT
  SELECT role, organization_id, organization_name 
  INTO v_creator_role, v_creator_org_id, v_creator_org_name 
  FROM public.users WHERE id = v_uid;

  -- Fallbacks if public profile missing (rare due to other fixes)
  IF v_creator_role IS NULL THEN
     v_creator_role := 'viewer'; 
  END IF;

  -- 2. DETERMINE ORGANIZATION
  -- Admin/SuperAdmin can specify any Org.
  -- Everyone else creates users in their OWN Org.
  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') THEN
    v_final_org_id := p_organization_id;
  ELSE
    v_final_org_id := v_creator_org_id; 
    -- Auto-fix Org Name if missing
    p_organization_name := COALESCE(p_organization_name, v_creator_org_name); 
  END IF;

  -- 3. CREATE USER (NO PERMISSION CHECK)
  -- The strict "IF...RAISE EXCEPTION" block is removed.
  
  INSERT INTO public.users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
  VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, p_organization_name, p_organization_type, p_description)
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    phone = EXCLUDED.phone,
    department = EXCLUDED.department,
    organization_id = EXCLUDED.organization_id,
    description = EXCLUDED.description,
    updated_at = now();

  -- 4. AUTO-CONFIRM EMAIL (For smooth login)
  UPDATE auth.users SET email_confirmed_at = now() WHERE id = p_id;
    
  RETURN (SELECT u FROM public.users u WHERE id = p_id);

END;
$$;

-- Log the change
DO $$
BEGIN
  RAISE NOTICE 'Universal User Creation enabled. Any user can now create other users.';
END $$;
