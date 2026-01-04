-- ============================================================================
-- FIX RLS RECURSION BUG (LOGIN LOOP)
-- Purpose: The previous fix used recursive queries (SELECT FROM users inside users policy).
--          This causes an infinite loop and fails queries -> Login fails -> No Route.
--          We fix this by using a SECURITY DEFINER function to read the role safely.
-- ============================================================================

-- 1. Helper Function to get Role without triggering RLS
CREATE OR REPLACE FUNCTION get_auth_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (SELECT role FROM users WHERE id = auth.uid());
END;
$$;

-- 2. Helper Function to get Organization ID without triggering RLS
CREATE OR REPLACE FUNCTION get_auth_user_org_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (SELECT organization_id FROM users WHERE id = auth.uid());
END;
$$;


-- 3. Update RLS Policies to use these Safe Functions
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view relevant profiles" ON users;
DROP POLICY IF EXISTS "Org Admins can update their staff" ON users;

-- View Policy (Non-Recursive)
CREATE POLICY "Users can view relevant profiles"
ON users FOR SELECT TO authenticated
USING (
  -- Admin sees all
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- Users see themselves
  id = auth.uid()
  OR
  -- Users see colleagues (if they have an org)
  (organization_id IS NOT NULL AND organization_id = get_auth_user_org_id())
);

-- Update Policy (Non-Recursive)
CREATE POLICY "Org Admins can update their staff"
ON users FOR UPDATE TO authenticated
USING (
  get_auth_user_role() IN ('organization', 'manager')
  AND 
  organization_id = get_auth_user_org_id()
);


