-- Fix Current User Role
-- USE THIS SCRIPT if you are getting "Unauthorized" errors when creating users.
-- It ensures your account has the 'organization' role permissions.

DO $$
DECLARE
  v_current_role text;
  v_email text;
BEGIN
  -- Get current details
  SELECT role, email INTO v_current_role, v_email
  FROM users 
  WHERE id = auth.uid();

  -- If user is missing in public.users, try to sync from auth.users
  IF v_current_role IS NULL THEN
      RAISE NOTICE 'User not found in public.users. Attempting to sync from auth...';
      
      INSERT INTO public.users (id, email, name, role, created_at, updated_at)
      SELECT id, email, COALESCE(raw_user_meta_data->>'name', 'Organization Admin'), 'organization', created_at, created_at
      FROM auth.users
      WHERE id = auth.uid()
      RETURNING role, email INTO v_current_role, v_email;
      
      RAISE NOTICE 'Synced user % from auth. Role set to %', v_email, v_current_role;
  ELSE
      RAISE NOTICE 'Current User: %, Role: %', v_email, v_current_role;
  END IF;

  -- If user is viewer or ordinary_user, promote them to organization
  IF v_current_role IN ('viewer', 'ordinary_user', 'field_worker') OR v_current_role IS NULL THEN
      UPDATE users
      SET role = 'organization'
      WHERE id = auth.uid();
      
      RAISE NOTICE 'SUCCESS: Upgraded user % to "organization" role.', v_email;
  ELSE
      RAISE NOTICE 'NO ACTION: User % already has role "%" (not viewer/ordinary_user).', v_email, v_current_role;
  END IF;
END $$;
