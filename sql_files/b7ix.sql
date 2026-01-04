/*
  RESTORE360 COMPLETE AUTH FIX
  
  This script fixes the "relation 'users' does not exist" error AND the RLS recursion loop.
  It performs a 3-step repair:
  1. Creates the missing 'users' table if it doesn't exist.
  2. Creates a secure function to handle role checks safely.
  3. Re-applies all necessary RLS policies without infinite recursion.

  INSTRUCTIONS:
  1. Go to Supabase Project Dashboard -> SQL Editor
  2. Copy/Paste this ENTIRE script
  3. Run it
*/

-- ============================================================================
-- PART 1: ENSURE USERS TABLE EXISTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text UNIQUE NOT NULL,
  name text NOT NULL,
  phone text,
  department text,
  role text NOT NULL DEFAULT 'viewer',
  user_type text DEFAULT 'individual', -- Added from context of other files
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS (safe to run if already enabled)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- PART 2: CREATE SECURE ROLE CHECK FUNCTION
-- ============================================================================

-- This function runs with "SECURITY DEFINER" privileges, meaning it bypasses RLS
-- This breaks the infinite loop of "checking RLS to see if you can check RLS"
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
  
  -- Return 'viewer' if role is null (safety fallback)
  RETURN COALESCE(v_role, 'viewer');
END;
$$;

-- ============================================================================
-- PART 3: RE-APPLY RLS POLICIES (CLEAN & NON-RECURSIVE)
-- ============================================================================

-- Drop ALL existing policies to ensure a clean slate
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
DROP POLICY IF EXISTS "Users can view own profile or admins view all" ON users;
DROP POLICY IF EXISTS "Users can update own profile or admins update all" ON users;
DROP POLICY IF EXISTS "Admins can delete users" ON users;

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
CREATE POLICY "Users can create own profile"
ON users FOR INSERT
TO authenticated
WITH CHECK (
  id = auth.uid()
  -- No admin check needed here usually, but if needed:
  -- OR get_current_user_role() IN ('admin', 'state_admin')
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
  1. The "relation 'users' does not exist" error will be gone.
  2. The 500 Internal Server Error Loop will be gone.
*/
