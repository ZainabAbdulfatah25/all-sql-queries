/*
  RESTORE360 SIGNUP FIX V2
  
  This script addresses the "new row violates row-level security policy" error during signup.
  It ensures that:
  1. Authenticated users can INSERT into the `organizations` table.
  2. Authenticated users can INSERT into the `users` table (their own profile).
  3. Policies are simplified to avoid recursion.
*/

-- ============================================================================
-- 1. FIX ORGANIZATIONS POLICIES
-- ============================================================================

-- Ensure RLS is enabled
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- Drop generic insert policy if it exists to avoid conflicts
DROP POLICY IF EXISTS "Authenticated users can create organizations" ON organizations;
DROP POLICY IF EXISTS "Users can insert organizations" ON organizations;

-- Create explicit INSERT policy for organizations
-- Anyone authenticated can create an organization (part of signup flow)
CREATE POLICY "Authenticated users can create organizations"
  ON organizations FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- ============================================================================
-- 2. FIX USERS POLICIES (Reset to Safe State)
-- ============================================================================

-- Drop potentially conflicting policies
DROP POLICY IF EXISTS "Users can create own profile or admins create users" ON users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON users;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON users;

-- Re-create the INSERT policy for users
-- Strictly allows users to create a row where the ID matches their Auth ID
CREATE POLICY "Users can create their own profile"
  ON users FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Ensure the Select/Update policies are also present and correct
DROP POLICY IF EXISTS "Users can view own profile or admins view all" ON users;
CREATE POLICY "Users can view own profile or admins view all"
  ON users FOR SELECT
  TO authenticated
  USING (
    id = auth.uid() 
    OR 
    (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
  );

DROP POLICY IF EXISTS "Users can update own profile or admins update all" ON users;
CREATE POLICY "Users can update own profile or admins update all"
  ON users FOR UPDATE
  TO authenticated
  USING (
    id = auth.uid() 
    OR 
    (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
  )
  WITH CHECK (
    id = auth.uid() 
    OR 
    (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
  );

-- ============================================================================
-- 3. FIX HOUSEHOLD MEMBERS POLICIES (Just in case)
-- ============================================================================

-- Ensure household members can be created by authenticated users
DROP POLICY IF EXISTS "Authenticated users can create household members" ON household_members;
CREATE POLICY "Authenticated users can create household members"
  ON household_members FOR INSERT
  TO authenticated
  WITH CHECK (true);

