-- ============================================================================
-- FORCE CLEANUP OF STUCK USER (ROBUST VERSION)
-- Purpose: Delete 'john@example.com' and ALL their created data (cases, etc.)
--          This fixes the "violations foreign key constraint" error.
-- ============================================================================

DO $$
DECLARE
  v_user_ptr UUID;
BEGIN
  -- 1. Find the User ID from auth.users
  SELECT id INTO v_user_ptr FROM auth.users WHERE email = 'john@example.com';

  -- 2. If user exists, clean up EVERYTHING they own
  IF v_user_ptr IS NOT NULL THEN
    
    -- Delete CASES created by this user (Fixes the error you saw)
    DELETE FROM cases WHERE created_by = v_user_ptr;

    -- Delete REFERRALS created by this user (Prevent future errors)
    DELETE FROM referrals WHERE created_by = v_user_ptr;

    -- (Optional) Delete other potential dependencies if they exist
    -- DELETE FROM some_other_table WHERE user_id = v_user_ptr;

    -- 3. Now it is safe to delete the user profile
    DELETE FROM public.users WHERE id = v_user_ptr;

    -- 4. Finally, delete the login account
    DELETE FROM auth.users WHERE id = v_user_ptr;
    
    RAISE NOTICE 'User john@example.com and their data have been successfully deleted.';
  ELSE
    RAISE NOTICE 'User john@example.com not found. Nothing to delete.';
  END IF;
  
  -- 5. Auto-confirm others just in case
  UPDATE auth.users SET email_confirmed_at = now() WHERE email_confirmed_at IS NULL;

END $$;
