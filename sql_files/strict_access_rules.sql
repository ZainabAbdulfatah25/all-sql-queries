-- ============================================================================
-- STRICT ACCESS RULES (Status Guard)
-- Purpose: 
-- 1. Prevent 'case_worker' (Individual) from changing registration status.
-- 2. Allow 'admin' and 'organization' to change status.
-- ============================================================================

CREATE OR REPLACE FUNCTION check_status_update_permission()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_role text;
BEGIN
  -- 1. Check if Status is actually changing
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- 2. Get User Role
  v_role := get_auth_user_role();

  -- 3. Define Privileged Roles
  IF v_role IN ('admin', 'state_admin', 'super_admin', 'organization', 'manager') THEN
    RETURN NEW; -- Allowed
  END IF;

  -- 4. Block Everyone Else (case_worker, viewer, etc)
  RAISE EXCEPTION 'Unauthorized: Only Admins and Organizations can update registration status.';
END;
$$;

DROP TRIGGER IF EXISTS check_status_update_permission ON registrations;
CREATE TRIGGER check_status_update_permission
BEFORE UPDATE ON registrations
FOR EACH ROW
EXECUTE FUNCTION check_status_update_permission();

-- Confirm RLS is still active and strict (from previous script)
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
