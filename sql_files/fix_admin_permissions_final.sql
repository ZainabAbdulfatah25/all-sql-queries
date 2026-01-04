-- ============================================================================
-- FIX ADMIN PERMISSIONS FINAL
-- Purpose: Forcefully set the current user (you) to 'admin' role.
--          This fixes the "Permission Denied (viewer)" error by correcting
--          the underlying data in both public and auth tables.
-- ============================================================================

DO $$
DECLARE
  v_email TEXT := 'zainab.abdulfatah@myitc.org'; -- TARGET EMAIL FROM SCREENSHOT
BEGIN
  -- 1. Force Public Profile to Admin
  UPDATE public.users 
  SET role = 'admin'
  WHERE email = v_email;

  -- 2. Force Auth Metadata to Admin (Crucial for RLS/Sessions)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    '"admin"'
  )
  WHERE email = v_email;

  RAISE NOTICE 'Force-promoted % to admin.', v_email;

END $$;
