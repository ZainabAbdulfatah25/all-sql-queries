-- ============================================================================
-- FIX AUTH & VISIBILITY (CRITICAL)
-- Purpose: Ensure users can log in, view their own profile, and view related Organization data.
--          Fixes "Dashboard not routing" caused by failed profile loading.
-- ============================================================================

-- 1. Organizations Table Visibility
--    (Required because User Profile joins with Organizations table)
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view all organizations" ON organizations;
DROP POLICY IF EXISTS "Users can view own organization" ON organizations;

-- Policy: Allow ALL authenticated users to view ALL organizations
-- (Reasoning: Service Directory feature requires this visibility)
CREATE POLICY "Authenticated users can view all organizations"
ON organizations FOR SELECT
TO authenticated
USING (true);

-- 2. Users Table Visibility (Reinforce Self-View)
DROP POLICY IF EXISTS "Enable Read Access for Authenticated Users" ON users;
DROP POLICY IF EXISTS "Users can view own profile" ON users;

CREATE POLICY "Enable Read Access for Authenticated Users"
ON users FOR SELECT
TO authenticated
USING (
  -- Users can ALWAYS see themselves
  auth.uid() = id
  OR
  -- Admins can see everyone
  (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'super_admin', 'state_admin')
  OR
  -- Organization Members can see others in same Org
  organization_id = (SELECT organization_id FROM users WHERE id = auth.uid())
);

-- 3. Fix Potential "User Record Not Found" for new Staff
--    (Optional: Grant permissions properly if missing)
GRANT SELECT ON organizations TO authenticated;
GRANT SELECT ON users TO authenticated;
