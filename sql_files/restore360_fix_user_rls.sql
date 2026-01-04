-- Fix User Visibility RLS (Recursive fix)
-- This script replaces the recursive policy with a safe one using SECURITY DEFINER functions.

-- 1. Create helper to get role safely (bypassing RLS)
CREATE OR REPLACE FUNCTION get_auth_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (SELECT role FROM users WHERE id = auth.uid());
END;
$$;

-- 2. Create helper to get org id safely
CREATE OR REPLACE FUNCTION get_auth_org_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (SELECT organization_id FROM users WHERE id = auth.uid());
END;
$$;

-- 3. Clean up the problematic policy
DROP POLICY IF EXISTS "Organization admins can view their own organization users" ON public.users;

-- 4. Create proper non-recursive policy
CREATE POLICY "Organization admins can view their own organization users"
ON public.users
FOR SELECT
TO authenticated
USING (
  -- Self access (always allowed)
  auth.uid() = id
  OR
  -- Global Admin access
  get_auth_role() IN ('admin', 'state_admin')
  OR
  -- Organization Admin/Manager access (view users in same org)
  (
    get_auth_role() IN ('organization', 'manager')
    AND
    organization_id = get_auth_org_id()
    AND
    organization_id IS NOT NULL
  )
);

-- 5. Grant permissions
GRANT EXECUTE ON FUNCTION get_auth_role TO authenticated;
GRANT EXECUTE ON FUNCTION get_auth_org_id TO authenticated;
