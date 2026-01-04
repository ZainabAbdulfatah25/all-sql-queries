/*
  RESTORE360 AUTH RECURSION FIX
  
  This script fixes the "Internal Server Error" (500) caused by infinite recursion 
  in the users table Row Level Security (RLS) policies.

  INSTRUCTIONS:
  1. Go to your Supabase Project Dashboard
  2. Open the SQL Editor
  3. Copy and paste this ENTIRE script
  4. Run it
*/

-- 1. Create a secure function to check user roles without triggering RLS
-- This function runs with "SECURITY DEFINER" privileges, meaning it bypasses RLS
CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  -- Get the role directly from the table
  SELECT role INTO v_role
  FROM users
  WHERE id = auth.uid();
  
  RETURN v_role;
END;
$$;

-- 2. Drop ALL existing policies on the users table to ensure a clean slate
-- We need to be aggressive here to remove any recursive policies
DROP POLICY IF EXISTS "Users can read own data" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Users can update own data" ON users;
DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Users can create own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can view based on role" ON users;
DROP POLICY IF EXISTS "Authorized users can create new users" ON users;
DROP POLICY IF EXISTS "Users can update based on role" ON users;
DROP POLICY IF EXISTS "Only admins can delete users" ON users;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON users;

-- 3. Create new, non-recursive policies

-- SELECT: Users can see themselves, Admins/State Admins can see everyone
CREATE POLICY "Users can view own profile or admins view all"
ON users FOR SELECT
TO authenticated
USING (
  id = auth.uid() 
  OR 
  get_current_user_role() IN ('admin', 'state_admin')
);

-- UPDATE: Users can update themselves, Admins/State Admins can update everyone
CREATE POLICY "Users can update own profile or admins update all"
ON users FOR UPDATE
TO authenticated
USING (
  id = auth.uid() 
  OR 
  get_current_user_role() IN ('admin', 'state_admin')
)
WITH CHECK (
  id = auth.uid() 
  OR 
  get_current_user_role() IN ('admin', 'state_admin')
);

-- INSERT: Authenticated users can create their own profile (on signup)
-- Admins can create other users (managed via edge functions usually, but allowing here for safety)
CREATE POLICY "Users can create own profile"
ON users FOR INSERT
TO authenticated
WITH CHECK (
  id = auth.uid() 
  OR 
  get_current_user_role() IN ('admin', 'state_admin')
);

-- DELETE: Only admins
CREATE POLICY "Admins can delete users"
ON users FOR DELETE
TO authenticated
USING (
  get_current_user_role() IN ('admin', 'state_admin')
);

/*
  VERIFICATION
  After running this, the 500 errors on the Login page should disappear.
*/
