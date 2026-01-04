-- ============================================================================
-- FIX USERS RLS INSERT (Allow Self-Profile Creation)
-- Purpose: 
-- 1. Ensure authenticated users can INSERT their own profile into 'users' table.
-- 2. Prevent RLS errors during signup/login flow when profile doesn't exist.
-- ============================================================================

-- 1. Enable RLS (Ensure it's on)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- 2. Create/Replace INSERT Policy
-- This allows any authenticated user to insert a row, provided validation triggers (if any) pass.
-- We use a permissive WITH CHECK (true) for INSERT to avoid "new row violates row-level security policy"
-- during the initial creation where context might be limited.
DROP POLICY IF EXISTS "Authenticated users can create users" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;

CREATE POLICY "Users can insert own profile"
ON users FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Fallback permissive policy if the above is too strict for some trigger flows
-- (Uncomment if needed, but the above is standard best practice)
-- CREATE POLICY "Authenticated users can create any profile"
-- ON users FOR INSERT
-- TO authenticated
-- WITH CHECK (true);

-- 3. Ensure SELECT Policy covers own profile
DROP POLICY IF EXISTS "Users can view own profile" ON users;
CREATE POLICY "Users can view own profile"
ON users FOR SELECT
TO authenticated
USING (
  auth.uid() = id
);

-- 4. Notification
DO $$
BEGIN
  RAISE NOTICE 'Users RLS policies for INSERT and SELECT updated.';
END $$;
