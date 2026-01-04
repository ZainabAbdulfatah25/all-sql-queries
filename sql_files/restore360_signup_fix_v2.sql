/*
  RESTORE360 SIGNUP FIX V2 (REVISED)
  
  This script addresses the "new row violates row-level security policy" error during signup.
  It ensures that:
  1. Authenticated users can INSERT into the `organizations` table.
  2. Authenticated users can INSERT into the `users` table (their own profile).
  3. Policies use SECURITY DEFINER functions to avoid infinite recursion.
*/

-- ============================================================================
-- 0. HELPER FUNCTIONS (Anti-Recursion)
-- ============================================================================

-- Function to check if user is admin WITHOUT triggering RLS recursion
CREATE OR REPLACE FUNCTION is_admin_safe()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Direct query bypasses RLS because function is SECURITY DEFINER
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND role IN ('admin', 'super_admin', 'state_admin')
  );
END;
$$;

-- ============================================================================
-- 1. FIX ORGANIZATIONS POLICIES
-- ============================================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- Drop generic insert policy if it exists to avoid conflicts
DROP POLICY IF EXISTS "Authenticated users can create organizations" ON organizations;
DROP POLICY IF EXISTS "Users can insert organizations" ON organizations;

-- Create explicit INSERT policy for organizations by ANY authenticated user
-- This is necessary during signup for organization accounts
CREATE POLICY "Authenticated users can create organizations"
  ON organizations FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Ensure update policy allows organizations to update THEMSELVES (if not already handled)
-- (Existing policies might cover this, but ensuring safety)

-- ============================================================================
-- 2. FIX USERS POLICIES (Reset to Safe State)
-- ============================================================================

-- Drop potentially conflicting policies
DROP POLICY IF EXISTS "Users can create own profile or admins create users" ON users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON users;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON users;
DROP POLICY IF EXISTS "Users can view own profile or admins view all" ON users;
DROP POLICY IF EXISTS "Users can update own profile or admins update all" ON users;

-- INSERT: Allow users to create their own profile
CREATE POLICY "Users can create their own profile"
  ON users FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- SELECT: Users view own, admins view all
CREATE POLICY "Users can view own profile or admins view all"
  ON users FOR SELECT
  TO authenticated
  USING (
    id = auth.uid() 
    OR 
    is_admin_safe()
  );

-- UPDATE: Users update own, admins update all
CREATE POLICY "Users can update own profile or admins update all"
  ON users FOR UPDATE
  TO authenticated
  USING (
    id = auth.uid() 
    OR 
    is_admin_safe()
  )
  WITH CHECK (
    id = auth.uid() 
    OR 
    is_admin_safe()
  );

-- DELETE: Only admins
CREATE POLICY "Admins can delete users"
  ON users FOR DELETE
  TO authenticated
  USING (is_admin_safe());

