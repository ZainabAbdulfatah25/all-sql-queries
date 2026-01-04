-- ============================================================================
-- RELINK DEFENSERA STAFF
-- Purpose: 
-- 1. Identify users who have 'Staff' roles (e.g. case_worker, field_officer) but NO Organization.
-- 2. Assign them to 'Defensera' (assuming they are the missing staff).
-- 3. Update their user_type to 'organization' so they are not wiped by 'individual' cleanup scripts.
-- ============================================================================

DO $$
DECLARE
  v_defensera_id UUID;
  v_count INTEGER;
BEGIN
  -- 1. Find Defensera ID
  SELECT id INTO v_defensera_id FROM organizations WHERE name ILIKE 'Defensera' LIMIT 1;

  IF v_defensera_id IS NULL THEN
    RAISE EXCEPTION 'Organization "Defensera" not found.';
  END IF;

  -- 2. Update Staff Roles to link to Defensera
  -- We exclude 'admin', 'state_admin' (System Admins) and 'viewer' (Ambiguous/Individual).
  -- All other roles imply organizational staff.
  UPDATE users
  SET 
    organization_id = v_defensera_id,
    organization_name = 'Defensera',
    user_type = 'organization', -- Mark as organization staff
    updated_at = now()
  WHERE 
    organization_id IS NULL -- Only target those currently without an org
    AND role NOT IN ('admin', 'state_admin', 'viewer', 'super_admin'); 

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Relinked % staff members to Defensera.', v_count;

  -- 3. OPTIONAL: Handle 'Viewer' if you have specific Viewers who are Defensera Staff.
  --    If you know their emails, you can add them manually like this:
  --    UPDATE users SET organization_id = v_defensera_id, organization_name = 'Defensera', user_type = 'organization' 
  --    WHERE email = 'specific_staff_viewer@example.com';

END $$;
