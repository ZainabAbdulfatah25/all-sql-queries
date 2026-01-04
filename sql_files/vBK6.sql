-- ============================================================================
-- FINAL ROLE FIX & HARDENING
-- Purpose: Fix "Role <NULL>" error by adding a fallback to auth metadata
--          and forcing a sync of the user profile.
-- ============================================================================

-- 1. Redefine admin_create_user with FALLBACK logic
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
  v_creator_role TEXT;
  v_creator_org_id UUID;
  v_final_org_id UUID;
  v_uid UUID;
BEGIN
  v_uid := auth.uid();

  -- Attempt 1: Get from public.users
  SELECT role, organization_id INTO v_creator_role, v_creator_org_id 
  FROM public.users WHERE id = v_uid;

  -- Attempt 2: If NULL, fallback to auth.users metadata (The Fail-Safe)
  IF v_creator_role IS NULL THEN
    SELECT 
      COALESCE(raw_user_meta_data->>'role', 'viewer') INTO v_creator_role
    FROM auth.users 
    WHERE id = v_uid;
    
    -- Also try to get org id if possible, otherwise leave null
    RAISE NOTICE 'Role was NULL in public.users, fetched % from auth system.', v_creator_role;
  END IF;

  -- Permission Check
  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') OR 
     (v_creator_role IN ('organization', 'manager') AND p_role NOT IN ('admin', 'super_admin', 'state_admin')) THEN
    
    -- Org Logic: If Org Admin, force new user into their Org
    IF v_creator_role IN ('organization', 'manager') THEN
      v_final_org_id := v_creator_org_id;
      -- If v_creator_org_id is null (data issue), try to use passed org or fail gracefully
      IF v_final_org_id IS NULL THEN 
         v_final_org_id := p_organization_id; 
      END IF;
    ELSE
      v_final_org_id := p_organization_id;
    END IF;

    -- UPSERT User
    INSERT INTO public.users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, p_organization_name, p_organization_type, p_description)
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone,
      department = EXCLUDED.department,
      organization_id = COALESCE(EXCLUDED.organization_id, users.organization_id),
      description = EXCLUDED.description,
      updated_at = now();

    -- Confirm Email
    UPDATE auth.users SET email_confirmed_at = now() WHERE id = p_id;
    
    RETURN (SELECT u FROM public.users u WHERE id = p_id);

  ELSE
    RAISE EXCEPTION 'Unauthorized: Role % (User %) cannot create user with role %', v_creator_role, v_uid, p_role;
  END IF;
END;
$$;


-- 2. FORCE SYNC (Again)
-- Ensure public profile exists for ALL auth users
INSERT INTO public.users (id, email, name, role, created_at, updated_at)
SELECT 
    id, email, 
    COALESCE(raw_user_meta_data->>'name', email), 
    COALESCE(raw_user_meta_data->>'role', 'viewer'),
    created_at, now()
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.users)
ON CONFLICT (id) DO NOTHING;


-- 3. FORCE PERMISSIONS (Specific Account)
DO $$
BEGIN
  -- Update Public Role
  UPDATE public.users 
  SET role = 'organization' 
  WHERE email = 'abdulfatahzainab3@gmail.com';

  -- Update Auth Metadata (for session token consistency)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    '"organization"'
  )
  WHERE email = 'abdulfatahzainab3@gmail.com';
  
  RAISE NOTICE 'Permissions forced for abdulfatahzainab3@gmail.com';
END $$;
