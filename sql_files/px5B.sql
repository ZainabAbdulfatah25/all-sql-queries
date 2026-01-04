-- Fix Defensera User Data and Link to Organization
-- This script finds the "Defensera" organization and links the user "defensera@example.com" to it.

DO $$
DECLARE
  v_org_id UUID;
  v_user_email TEXT := 'defensera@example.com';
BEGIN
  -- 1. Find the organization
  -- Try exact match on 'organization_name' or 'name'
  SELECT id INTO v_org_id 
  FROM organizations 
  WHERE organization_name ILIKE 'Defensera' OR name ILIKE 'Defensera'
  LIMIT 1;

  -- If not found, create it? No, assumed to exist. If query fails, v_org_id is null.
  
  IF v_org_id IS NOT NULL THEN
      RAISE NOTICE 'Found Organization ID: %', v_org_id;

      -- 2. Update the user
      UPDATE users 
      SET 
        organization_id = v_org_id,
        role = 'organization', -- Ensure role is correct
        organization_name = 'Defensera'
      WHERE email ILIKE v_user_email;
      
      -- 3. Ensure the organization itself is active
      UPDATE organizations SET is_active = true WHERE id = v_org_id;
      
      RAISE NOTICE 'Updated user % with organization_id %', v_user_email, v_org_id;
  ELSE
      RAISE NOTICE 'Organization "Defensera" not found. Creating it...';
      
      INSERT INTO organizations (name, organization_name, contact_email, is_active, type)
      VALUES ('Defensera', 'Defensera', v_user_email, true, 'NGO')
      RETURNING id INTO v_org_id;
      
      UPDATE users 
      SET 
        organization_id = v_org_id,
        role = 'organization',
        organization_name = 'Defensera'
      WHERE email ILIKE v_user_email;
      
      RAISE NOTICE 'Created Organization and updated user.';
  END IF;
  
  -- 4. Just in case, grant permissions again? No, RLS handles it.
END $$;
