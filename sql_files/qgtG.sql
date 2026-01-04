/*
  RESTORE360 MANUAL USER FIX
  
  Target User: abdulfatahzainab3@gmail.com
  Target Org: Defensera (NGO)
  
  Issue: User is stuck as 'viewer' role due to previous signup failures.
  Fix: Manually promote role and link to organization.
*/

DO $$
DECLARE
  target_email text := 'abdulfatahzainab3@gmail.com';
  target_org_name text := 'Defensera';
  v_user_id uuid;
  v_org_id uuid;
BEGIN
  -- 1. Get User ID
  SELECT id INTO v_user_id FROM users WHERE email = target_email;
  
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'User % found in public.users not found. Checking auth.users...', target_email;
    -- Try to sync from auth if missing in public
    INSERT INTO public.users (id, email, name, role, created_at, updated_at)
    SELECT id, email, split_part(email, '@', 1), 'organization', created_at, created_at
    FROM auth.users WHERE email = target_email
    RETURNING id INTO v_user_id;
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User % does not exist in Auth or Public tables.', target_email;
  END IF;

  -- 2. Get or Create Organization
  SELECT id INTO v_org_id FROM organizations WHERE name = target_org_name;
  
  IF v_org_id IS NULL THEN
    INSERT INTO organizations (name, organization_name, type, email, is_active, sectors_provided, locations_covered, created_by)
    VALUES (
      target_org_name, 
      target_org_name, 
      'NGO', 
      target_email, 
      true, 
      ARRAY['Protection', 'Health'], -- Defaults to match screenshot/context
      ARRAY['Maiduguri'], 
      v_user_id
    )
    RETURNING id INTO v_org_id;
    RAISE NOTICE 'Created missing organization: %', target_org_name;
  ELSE
    RAISE NOTICE 'Found existing organization: %', target_org_name;
  END IF;

  -- 3. Update User Profile
  UPDATE users
  SET 
    role = 'organization',
    user_type = 'organization',
    organization_id = v_org_id,
    organization_name = target_org_name,
    organization_type = 'NGO'
  WHERE id = v_user_id;
  
  RAISE NOTICE 'Successfully updated user % to Organization Admin for %', target_email, target_org_name;

END $$;
