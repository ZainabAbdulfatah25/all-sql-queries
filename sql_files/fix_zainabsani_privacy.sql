-- ============================================================================
-- FIX PRIVACY FOR zainabsani@example.com
-- Purpose: 
-- 1. Unlink from any organization (set to NULL).
-- 2. Downgrade Role to 'case_worker' (Individual).
-- 3. Force Sync Metadata so RLS kicks in immediately.
-- ============================================================================

DO $$
DECLARE
  v_email text := 'zainabsani@example.com';
BEGIN
  -- 1. Update Public Profile
  UPDATE public.users 
  SET 
    organization_id = NULL, 
    organization_name = NULL, 
    role = 'case_worker'
  WHERE email = v_email;

  -- 2. Update Auth Metadata (Crucial for JWT)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_build_object(
    'role', 'case_worker',
    'organization_id', NULL
  )
  WHERE email = v_email;
  
  RAISE NOTICE 'Fixed privacy for %', v_email;
END $$;
