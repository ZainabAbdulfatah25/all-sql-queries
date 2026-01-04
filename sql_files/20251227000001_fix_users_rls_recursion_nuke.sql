/*
  # Fix Infinite Recursion - The "Nuke" Approach

  ## Problem
  The "infinite recursion" error persists, likely because some old policies on the `users` table
  were not successfully dropped by name (perhaps due to naming mismatches or previous failed migrations).

  ## Solution
  1. Use a `DO` block to dynamically find and drop **ALL** policies on the `users` table.
     This ensures we start with a completely clean slate for this table.
  2. Recreate the `is_admin_safe` function (SECURITY DEFINER).
  3. Recreate the simple, non-recursive policies.

  ## Safety
  - This script only affects the `users` table policies.
  - It preserves the data and table structure.
*/

-- ============================================================================
-- 1. DYNAMICALLY DROP ALL POLICIES ON USERS TABLE
-- ============================================================================

DO $$
DECLARE
  pol record;
BEGIN
  -- Loop through all policies on the 'users' table in the 'public' schema
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE tablename = 'users'
    AND schemaname = 'public'
  LOOP
    -- Execute DROP POLICY for each found policy
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users', pol.policyname);
    RAISE NOTICE 'Dropped policy: %', pol.policyname;
  END LOOP;
END $$;

-- ============================================================================
-- 2. ENSURE SECURITY DEFINER FUNCTION EXISTS
-- ============================================================================

CREATE OR REPLACE FUNCTION is_admin_safe()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- This query runs with the privileges of the function creator (usually postgres),
  -- effectively bypassing RLS on the users table.
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND role IN ('admin', 'super_admin', 'state_admin')
  );
END;
$$;

-- ============================================================================
-- 3. RECREATE POLICIES (Simplified & Safe)
-- ============================================================================

-- SELECT: Users can view their own profile, admins can view all
CREATE POLICY "Users can view own profile or admins view all"
  ON users FOR SELECT
  TO authenticated
  USING (
    id = auth.uid() 
    OR 
    is_admin_safe()
  );

-- INSERT: Allow authenticated users to create their own profile during signup
-- Also allow admins to create users
CREATE POLICY "Users can create own profile or admins create users"
  ON users FOR INSERT
  TO authenticated
  WITH CHECK (
    id = auth.uid()
    OR
    is_admin_safe()
  );

-- UPDATE: Users can update their own profile, admins can update all
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

-- DELETE: Only admins can delete users
CREATE POLICY "Admins can delete users"
  ON users FOR DELETE
  TO authenticated
  USING (
    is_admin_safe()
  );
