-- ============================================================================
-- FIX RLS INFINITE RECURSION
-- Issue: Policies on 'users' table were checking 'users' table (recursion).
-- Fix: Use SECURITY DEFINER functions to bypass RLS when checking permissions.
-- ============================================================================

-- 1. Create Helper Functions (Bypass RLS)

-- Function to get the current user's role without triggering RLS
CREATE OR REPLACE FUNCTION get_auth_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with privileges of creator (postgres), bypassing RLS
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role
  FROM users
  WHERE id = auth.uid();
  
  RETURN v_role;
END;
$$;

-- Function to get the current user's organization_id without triggering RLS
CREATE OR REPLACE FUNCTION get_auth_user_organization_id()
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

-- 2. Update Users Table Policies

-- Enable RLS (ensure it's on)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Drop existing problematic policies
DROP POLICY IF EXISTS "Enable Read Access for Authenticated Users" ON users;
DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Authenticated users can view all organizations" ON organizations; -- Just incase

-- Create Non-Recursive Policy
CREATE POLICY "Enable Read Access for Authenticated Users"
ON users FOR SELECT
TO authenticated
USING (
  -- 1. Users can ALWAYS see themselves (id check is fast)
  auth.uid() = id
  OR
  -- 2. Admins can see everyone (uses secure function)
  get_auth_user_role() IN ('admin', 'super_admin', 'state_admin')
  OR
  -- 3. Organization Members can see others in same Org (uses secure function)
  organization_id = get_auth_user_organization_id()
);

-- 3. Re-apply Organizations Policy for completeness (Non-recursive)
-- (This one was usually fine, but good to ensure consistent state)
DROP POLICY IF EXISTS "Authenticated users can view all organizations" ON organizations;

CREATE POLICY "Authenticated users can view all organizations"
ON organizations FOR SELECT
TO authenticated
USING (true); -- Publicly visible to authenticated users (as per Service Directory requirements)
