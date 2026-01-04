-- ============================================================================
-- ADOPT ALL ORPHAN USERS
-- Purpose: Forcefully show ALL registered users by assigning any "floating" 
--          users to the main 'Defensera' organization.
-- ============================================================================

DO $$
DECLARE
  v_defensera_id UUID;
  v_count INTEGER;
BEGIN
  -- 1. Find Defensera ID
  SELECT id INTO v_defensera_id FROM organizations WHERE name ILIKE 'Defensera' LIMIT 1;

  IF v_defensera_id IS NULL THEN
    RAISE EXCEPTION 'Organization "Defensera" not found. Please create it first.';
  END IF;

  -- 2. SYNC: Make sure every Auth user has a Public Profile
  INSERT INTO public.users (id, email, name, role, created_at, updated_at)
  SELECT 
      id, email, 
      COALESCE(raw_user_meta_data->>'name', email), 
      COALESCE(raw_user_meta_data->>'role', 'viewer'),
      created_at, now()
  FROM auth.users
  WHERE id NOT IN (SELECT id FROM public.users)
  ON CONFLICT (id) DO NOTHING;

  -- 3. ADOPT: Assign ANY user with no Org to Defensera
  UPDATE users
  SET 
    organization_id = v_defensera_id,
    organization_name = 'Defensera',
    updated_at = now()
  WHERE organization_id IS NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RAISE NOTICE 'Adopted % orphan users into Defensera.', v_count;

END $$;
