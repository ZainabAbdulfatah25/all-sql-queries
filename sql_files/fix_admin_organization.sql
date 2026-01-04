-- ============================================================================
-- FIX ADMIN ORGANIZATION DATA
-- Purpose: 
-- 1. Ensure 'MyIT Consult Ltd' exists as the Admin Organization.
-- 2. Move Admin User (zainab.abdulfatah) to this Org.
-- 3. Move users created by Admin (currently in Defensera) to this Org.
-- ============================================================================

DO $$
DECLARE
  v_admin_org_id UUID;
  v_defensera_id UUID;
  v_admin_id UUID;
BEGIN
  -- 1. Get or Create 'MyIT Consult Ltd'
  SELECT id INTO v_admin_org_id FROM organizations WHERE name ILIKE 'MyIT Consult Ltd' LIMIT 1;

  IF v_admin_org_id IS NULL THEN
    INSERT INTO organizations (name, organization_name, type, email, is_active, created_at, updated_at)
    VALUES ('MyIT Consult Ltd', 'MyIT Consult Ltd', 'Admin', 'admin@myitconsult.org', true, now(), now())
    RETURNING id INTO v_admin_org_id;
    RAISE NOTICE 'Created Organization: MyIT Consult Ltd';
  END IF;

  -- 2. Find Admin User (zainab.abdulfatah)
  SELECT id INTO v_admin_id FROM public.users WHERE email ILIKE 'zainab.abdulfatah%' LIMIT 1;
  
  IF v_admin_id IS NOT NULL THEN
    -- Update Admin's Org
    UPDATE public.users 
    SET 
      organization_id = v_admin_org_id,
      organization_name = 'MyIT Consult Ltd'
    WHERE id = v_admin_id;
    
    -- Sync Auth Metadata for Admin
    UPDATE auth.users
    SET raw_user_meta_data = jsonb_set(
      jsonb_set(
        COALESCE(raw_user_meta_data, '{}'::jsonb),
        '{organization_name}',
        '"MyIT Consult Ltd"'
      ),
      '{organization_id}',
      to_jsonb(v_admin_org_id)
    )
    WHERE id = v_admin_id;
    
    RAISE NOTICE 'Moved Admin User to MyIT Consult Ltd';
  END IF;

  -- 3. Move "Defensera" users who should be "MyIT Consult Ltd"
  -- (Logic: If they are 'field_officer', 'case_worker', etc. and were created recently/manually, 
  -- they might be intended for the Admin Org. Use a safe update for now.)
  
  -- Update users linked to 'Defensera' but who are likely system users (e.g. zaks@example.com)
  -- We will move ALL users currently in 'Defensera' to 'MyIT Consult Ltd' IF they are not specifically strictly 'Defensera' logic
  -- Actually, let's just move the specific example users the user showed: 'zaks@example.com', 'bashirh@example.com'
  
  UPDATE public.users
  SET 
    organization_id = v_admin_org_id,
    organization_name = 'MyIT Consult Ltd'
  WHERE email IN ('zaks@example.com', 'bashirh@example.com', 'zainabsalman@example.com', 'zainabsani@example.com', 'salmahadi1@example.com', 'salmahadi@example.com');

  RAISE NOTICE 'Moved example users to MyIT Consult Ltd';

END $$;
