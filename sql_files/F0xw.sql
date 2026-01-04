-- ============================================================================
-- FIX DEFENSERA ORGANIZATION LINKAGE
-- Purpose: Ensure 'Defensera' organization exists and ALL its staff are linked to it.
--          This fixes the issue where added users are hidden from the list.
-- ============================================================================

DO $$
DECLARE
  v_org_id UUID;
BEGIN
  -- 1. Ensure Organization 'Defensera' exists
  SELECT id INTO v_org_id FROM organizations WHERE name ILIKE 'Defensera';
  
  IF v_org_id IS NULL THEN
    INSERT INTO organizations (name, organization_name, type, is_active, created_at, updated_at)
    VALUES ('Defensera', 'Defensera', 'NGO', true, now(), now())
    RETURNING id INTO v_org_id;
    RAISE NOTICE 'Created Organization Defensera with ID: %', v_org_id;
  ELSE
    RAISE NOTICE 'Found existing Organization Defensera with ID: %', v_org_id;
  END IF;

  -- 2. Link ALL users who claim to be 'Defensera' to this ID
  --    This fixes your main account AND the new user 'bashir' if he was created with the name but no ID.
  UPDATE users
  SET 
    organization_id = v_org_id,
    organization_name = 'Defensera' -- Standardize name spacing/casing
  WHERE 
    organization_name ILIKE 'Defensera' 
    OR email ILIKE '%abdulfatahzainab%' -- Ensure your main accounts are caught
    OR email = 'bashir@example.com';    -- Ensure the specific new user is caught

  RAISE NOTICE 'Updated users to link to Defensera (ID: %)', v_org_id;

END $$;
