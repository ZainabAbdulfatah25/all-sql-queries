/*
  # Fix Infinite Recursion in Users RLS Policies - Final Fix

  ## Problem
  The "infinite recursion detected in policy for relation 'users'" error occurs when RLS policies on the `users` table
  query the `users` table itself (directly or indirectly) to determine permissions. This creates a loop.

  ## Solution
  1. Drop ALL existing policies on the `users` table to ensure a clean slate.
  2. Create a `SECURITY DEFINER` function `is_admin_safe()` to check for admin status without triggering RLS.
  3. Create new, simplified policies that avoid self-referencing queries:
     - **View**: Users can view their own profile (`id = auth.uid()`). Admins can view all (using `is_admin_safe()`).
     - **Update**: Users can update their own profile. Admins can update all.
     - **Insert**: Authenticated users can insert their own profile (for signup).
     - **Delete**: Admins can delete users.

  ## Security
  - The `is_admin_safe()` function runs with the privileges of the creator (postgres/superuser), bypassing RLS.
  - This prevents the recursion loop while still enforcing role-based access control.
*/

-- ============================================================================
-- 1. DROP ALL EXISTING POLICIES ON USERS TABLE
-- ============================================================================

DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Users can create own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can read own data" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Users can update own data" ON users;
DROP POLICY IF EXISTS "Users can view based on role" ON users;
DROP POLICY IF EXISTS "Authorized users can create new users" ON users;
DROP POLICY IF EXISTS "Users can update based on role" ON users;
DROP POLICY IF EXISTS "Only admins can delete users" ON users;
-- Drop any other potential policies
DROP POLICY IF EXISTS "Users can view all users" ON users;
DROP POLICY IF EXISTS "Admins can view all users" ON users;
DROP POLICY IF EXISTS "Admins can update all users" ON users;
DROP POLICY IF EXISTS "Admins can delete all users" ON users;


-- ============================================================================
-- 2. CREATE SECURITY DEFINER HELPER FUNCTION
-- ============================================================================

-- Function to check if current user is admin (SAFE version - bypasses RLS)
CREATE OR REPLACE FUNCTION is_admin_safe()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER -- This is the key: runs as owner, bypassing RLS
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND role IN ('admin', 'super_admin', 'state_admin')
  );
END;
$$;

-- ============================================================================
-- 3. CREATE NEW NON-RECURSIVE POLICIES
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
