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

  RAISE NOTICE 'Current User: %, Role: %', v_email, v_current_role;

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
