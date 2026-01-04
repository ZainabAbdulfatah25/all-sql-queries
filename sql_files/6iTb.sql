/*
  RESTORE360 SIGNUP FIX V3 (THE NUKE)
  
  This script creates a clean slate for 'users' and 'organizations' RLS policies.
  It programmatically removes ALL existing policies to ensure no hidden rules are blocking signups.
  Then it reapplies the correct, tested policies.
*/

-- ============================================================================
-- 0. SAFE ADMIN CHECK FUNCTION
-- ============================================================================
CREATE OR REPLACE FUNCTION is_admin_safe()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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
-- 1. CLEAN SLATE: DROP ALL POLICIES
-- ============================================================================

DO $$
DECLARE
  pol record;
BEGIN
  -- Drop polices for 'users'
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'users' AND schemaname = 'public' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users', pol.policyname);
  END LOOP;
  
  -- Drop polices for 'organizations'
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'organizations' AND schemaname = 'public' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.organizations', pol.policyname);
  END LOOP;
END $$;

-- ============================================================================
-- 2. USERS TABLE POLICIES (Re-Apply)
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- INSERT: Self-creation allowed
CREATE POLICY "Users can insert own profile"
  ON users FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- SELECT: Self + Admins
CREATE POLICY "Users can view own profile or admins view all"
  ON users FOR SELECT
  TO authenticated
  USING (
    id = auth.uid() 
    OR 
    is_admin_safe()
  );

-- UPDATE: Self + Admins
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

-- DELETE: Admins only
CREATE POLICY "Admins can delete users"
  ON users FOR DELETE
  TO authenticated
  USING (is_admin_safe());

-- ============================================================================
-- 3. ORGANIZATIONS TABLE POLICIES (Re-Apply)
-- ============================================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- INSERT: Any authenticated user can create an organization (for signup)
CREATE POLICY "Authenticated users can create organizations"
  ON organizations FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- SELECT: Admins + Org Members + Active Orgs (Public)
CREATE POLICY "Role-based organization access"
  ON organizations FOR SELECT
  TO authenticated
  USING (
    is_admin_safe()
    OR
    (
      EXISTS (
        SELECT 1 FROM users
        WHERE users.id = auth.uid()
        AND users.organization_id = organizations.id
      )
    )
    OR
    is_active = true
  );

-- UPDATE: Admins + Org Members (Self-update)
CREATE POLICY "Authorized users can update organizations"
  ON organizations FOR UPDATE
  TO authenticated
  USING (
    is_admin_safe()
    OR
    (
      -- We must DIRECTLY check user table context without recursion for simple updates
      EXISTS (
        SELECT 1 FROM users
        WHERE users.id = auth.uid()
        AND users.organization_id = organizations.id
      )
    )
  )
  WITH CHECK (
    is_admin_safe()
    OR
    (
      EXISTS (
        SELECT 1 FROM users
        WHERE users.id = auth.uid()
        AND users.organization_id = organizations.id
      )
    )
  );

