/*
  RESTORE360 User View Permissions Fix
  
  Problem: "User not found" error when admin tries to view other users.
  Cause: Missing RLS policy allowing Admins to SELECT (view) other users.
  Solution: Add a SELECT policy that uses the secure is_admin() function.
  
  INSTRUCTIONS:
  1. Go to Supabase Dashboard > SQL Editor
  2. Copy/Paste this entire script
  3. Run
*/

-- 1. Ensure is_admin function exists and is secure (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND role = 'admin'
  );
END;
$$;

-- 2. Add SELECT policy for Admins
-- Drop existing view policy if it's too restrictive (optional, but "Users can view own profile" usually exists)
-- We will ADD a new policy for Admins.

DO $$
BEGIN
  DROP POLICY IF EXISTS "Admins can view all users" ON users;
  
  CREATE POLICY "Admins can view all users"
    ON users FOR SELECT
    TO authenticated
    USING (
      is_admin()
    );
END $$;

-- 3. Add policy for Organization Admins to view their own organization members
CREATE OR REPLACE FUNCTION get_my_org_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id
  FROM users
  WHERE id = auth.uid();
  RETURN v_org_id;
END;
$$;

DO $$
BEGIN
  DROP POLICY IF EXISTS "Org Admins can view org users" ON users;

  CREATE POLICY "Org Admins can view org users"
    ON users FOR SELECT
    TO authenticated
    USING (
      organization_id = get_my_org_id()
      AND organization_id IS NOT NULL
      AND (
        EXISTS (
           SELECT 1 FROM users 
           WHERE id = auth.uid() 
           AND role IN ('organization', 'manager')
        )
      )
    );
END $$;
