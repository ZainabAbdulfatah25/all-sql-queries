-- Cleanup Broken User Script
-- Attempts to delete a user by email to allow re-creation.

DO $$
DECLARE
  target_email text := 'mustaphasm2020@gmail.com'; -- The stuck email
  v_user_id uuid;
BEGIN
  -- 1. Find the user ID from public users OR auth users
  SELECT id INTO v_user_id FROM auth.users WHERE email = target_email;

  IF v_user_id IS NOT NULL THEN
      -- Delete from public (cascade should handle it, but being explicit)
      DELETE FROM public.users WHERE id = v_user_id;
      
      -- Delete from auth (Requires specific permissions, might fail if not superuser)
      -- NOTE: In Supabase SQL Editor, this usually works.
      DELETE FROM auth.users WHERE id = v_user_id;
      
      RAISE NOTICE 'Successfully deleted user %', target_email;
  ELSE
      RAISE NOTICE 'User % not found in Auth system.', target_email;
  END IF;
  
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error cleaning up user: %. Try using a DIFFERENT email address instead.', SQLERRM;
END $$;
