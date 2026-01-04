-- ============================================================================
-- FIX USER CREATION INHERITANCE
-- Purpose: 
-- 1. Ensure created users INHERIT the creator's organization if not specified.
--    (Even for Admins: If Admin doesn't pick an Org, use Admin's Org).
-- 2. Fix recent user 'xxeeeeexee' to be in 'MyIT Consult Ltd'.
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
  v_final_org_name TEXT;
BEGIN
  v_uid := auth.uid();

  -- 1. GET CREATOR CONTEXT
  SELECT role, organization_id, organization_name 
  INTO v_creator_role, v_creator_org_id, v_creator_org_name 
  FROM public.users WHERE id = v_uid;

  -- Fallbacks
  IF v_creator_role IS NULL THEN v_creator_role := 'viewer'; END IF;

  -- 2. DETERMINE ORGANIZATION (Smart Inheritance)
  
  -- Logic: Start with what was passed
  v_final_org_id := p_organization_id;
  v_final_org_name := p_organization_name;

  -- If Admin didn't specify, OR if user is not Admin -> Use Creator's Org
  IF (v_final_org_id IS NULL) OR (v_creator_role NOT IN ('admin', 'super_admin', 'state_admin')) THEN
     v_final_org_id := v_creator_org_id;
     v_final_org_name := v_creator_org_name;
  END IF;

  -- 3. CREATE USER
  INSERT INTO public.users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
  VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, v_final_org_name, p_organization_type, p_description)
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    phone = EXCLUDED.phone,
    department = EXCLUDED.department,
    organization_id = EXCLUDED.organization_id,
    organization_name = EXCLUDED.organization_name,
    description = EXCLUDED.description,
    updated_at = now();

  -- 4. AUTO-CONFIRM
  UPDATE auth.users SET email_confirmed_at = now() WHERE id = p_id;
    
  RETURN (SELECT u FROM public.users u WHERE id = p_id);
END;
$$;


-- ============================================================================
-- FIX: Repair user 'xxeeeeexee' (and others) to inherit Admin's Org
-- ============================================================================
DO $$
DECLARE
  v_admin_org_id UUID;
BEGIN
  -- Get correct Admin Org
  SELECT id INTO v_admin_org_id FROM organizations WHERE name = 'MyIT Consult Ltd';

  -- Fix 'xxeeeeexee'
  UPDATE public.users 
  SET organization_id = v_admin_org_id, organization_name = 'MyIT Consult Ltd'
  WHERE email LIKE 'xee@%' AND organization_name = 'Defensera';

  RAISE NOTICE 'Fixed organization inheritance logic and repaired recent users.';
END $$;
