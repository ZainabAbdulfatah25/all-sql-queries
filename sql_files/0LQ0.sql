-- ============================================================================
-- FIX USER LIST VISIBILITY
-- Purpose: Create a trusted function to fetch users, bypassing complex RLS issues.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with superuser privileges to bypass RLS on the table
SET search_path = public
AS $$
DECLARE
  v_user_role TEXT;
  v_org_id UUID;
BEGIN
  -- Get current user's role and organization securely
  SELECT role, organization_id INTO v_user_role, v_org_id
  FROM users
  WHERE id = auth.uid();

  IF v_user_role IN ('admin', 'state_admin', 'super_admin') THEN
     -- Admins see everyone
     RETURN QUERY SELECT * FROM users ORDER BY created_at DESC;
     
  ELSIF v_org_id IS NOT NULL THEN
     -- Organization members see everyone in their organization
     -- PLUS they see themselves (just in case they were somehow orphaned, though unlikely)
     RETURN QUERY 
     SELECT * FROM users 
     WHERE organization_id = v_org_id 
        OR id = auth.uid()
     ORDER BY created_at DESC;
     
  ELSE
     -- Fallback for users without an org (e.g., individual viewers): Only see themselves
     RETURN QUERY SELECT * FROM users WHERE id = auth.uid();
  END IF;
END;
$$;
