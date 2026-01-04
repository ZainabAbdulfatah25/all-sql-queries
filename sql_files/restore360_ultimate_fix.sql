-- ============================================================================
-- RESTORE360 ULTIMATE FIX
-- ============================================================================
-- This script fixes:
-- 1. "No users found" (Data Linkage & Visibility)
-- 2. "Unauthorized" creating users (Permission Logic)
-- 3. "Invalid credentials" (Email Confirmation)
-- 4. RLS Policy Conflicts
-- ============================================================================

DO $$
BEGIN

  -- --------------------------------------------------------------------------
  -- STEP 1: HEAL DATA (Link Users to Organizations)
  -- --------------------------------------------------------------------------
  -- Ensure Organizations exist for every user who claims one
  INSERT INTO organizations (name, organization_name, type, is_active, created_at, updated_at)
  SELECT DISTINCT u.organization_name, u.organization_name, 'NGO', true, now(), now()
  FROM users u
  WHERE u.organization_name IS NOT NULL AND u.organization_name != ''
  AND NOT EXISTS (SELECT 1 FROM organizations o WHERE o.name = u.organization_name);

  -- Link users to their Organization ID
  UPDATE users u
  SET organization_id = o.id
  FROM organizations o
  WHERE (u.organization_name = o.name OR u.organization_name = o.organization_name)
    AND u.organization_id IS NULL;

  -- Sync Auth Users to Public Users (Restore missing profiles)
  INSERT INTO public.users (id, email, name, role, created_at, updated_at)
  SELECT 
      id, email, 
      COALESCE(raw_user_meta_data->>'name', email), 
      COALESCE(raw_user_meta_data->>'role', 'viewer'),
      created_at, now()
  FROM auth.users
  WHERE id NOT IN (SELECT id FROM public.users)
  ON CONFLICT (id) DO NOTHING;

  -- Auto-Confirm Emails (Fixes Login)
  UPDATE auth.users SET email_confirmed_at = now() WHERE email_confirmed_at IS NULL;

  RAISE NOTICE 'Step 1: Data Healed & Synced.';


  -- --------------------------------------------------------------------------
  -- STEP 2: FIX ROOT PERMISSIONS (Your Account)
  -- --------------------------------------------------------------------------
  -- Ensure YOU are an Organization Admin
  UPDATE users 
  SET role = 'organization' 
  WHERE email = 'abdulfatahzainab3@gmail.com';
  
  -- Force update the metadata in auth.users too (so session gets it on next login)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    '"organization"'
  )
  WHERE email = 'abdulfatahzainab3@gmail.com';

  RAISE NOTICE 'Step 2: Permissions Fixed for Admin.';

END $$;


-- --------------------------------------------------------------------------
-- STEP 3: REDEFINE CRITICAL FUNCTIONS
-- --------------------------------------------------------------------------

-- FUNCTION: get_all_users (Visibility Filter)
CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_org_id UUID;
BEGIN
  SELECT role, organization_id INTO v_role, v_org_id FROM users WHERE id = auth.uid();

  IF v_role IN ('admin', 'state_admin', 'super_admin') THEN
     RETURN QUERY SELECT * FROM users ORDER BY created_at DESC;
  ELSE
     -- Org members see their org, plus themselves
     RETURN QUERY 
     SELECT * FROM users 
     WHERE organization_id = v_org_id OR id = auth.uid()
     ORDER BY created_at DESC;
  END IF;
END;
$$;


-- FUNCTION: admin_create_user (User Creation Logic)
CREATE OR REPLACE FUNCTION admin_create_user(
  p_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_organization_name TEXT DEFAULT NULL,
  p_organization_type TEXT DEFAULT NULL,
  p_organization_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_role TEXT;
  v_creator_org_id UUID;
  v_final_org_id UUID;
BEGIN
  -- Get Creator Info
  SELECT role, organization_id INTO v_creator_role, v_creator_org_id 
  FROM users WHERE id = auth.uid();

  -- Permission Check: 
  -- 1. Admins can create anyone.
  -- 2. Org/Managers can create non-admins.
  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') OR 
     (v_creator_role IN ('organization', 'manager') AND p_role NOT IN ('admin', 'super_admin', 'state_admin')) THEN
    
    -- If Org Admin, force the new user into their Org
    IF v_creator_role IN ('organization', 'manager') THEN
      v_final_org_id := v_creator_org_id;
    ELSE
      v_final_org_id := p_organization_id;
    END IF;

    -- UPSERT User
    INSERT INTO users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, p_organization_name, p_organization_type, p_description)
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      organization_id = EXCLUDED.organization_id; -- Ensure linkage is fixed on update too

    -- Auto-confirm the new user immediately
    UPDATE auth.users SET email_confirmed_at = now() WHERE id = p_id;
    
    RETURN (SELECT u FROM users u WHERE id = p_id);

  ELSE
    RAISE EXCEPTION 'Unauthorized: Role % cannot create user with role %', v_creator_role, p_role;
  END IF;
END;
$$;


-- --------------------------------------------------------------------------
-- STEP 4: RESET RLS POLICIES (Simple & Robust)
-- --------------------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view users" ON users;
DROP POLICY IF EXISTS "Org members can view their colleagues" ON users;
DROP POLICY IF EXISTS "Org Admins can update their staff" ON users;
DROP POLICY IF EXISTS "Authenticated users can view all organizations" ON organizations;


-- ORGANIZATION VISIBILITY
CREATE POLICY "Everyone can see organizations" 
ON organizations FOR SELECT TO authenticated USING (true);


-- USER VISIBILITY (Direct Select)
-- Note: 'get_all_users' RPC bypasses this, but this is needed for single-item lookups (like Profile View)
CREATE POLICY "Users can view relevant profiles"
ON users FOR SELECT TO authenticated
USING (
  -- Admin sees all
  (SELECT role FROM users WHERE id = auth.uid()) IN ('admin', 'state_admin')
  OR
  -- Users see themselves
  id = auth.uid()
  OR
  -- Users see colleagues (if they have an org)
  (organization_id IS NOT NULL AND organization_id = (SELECT organization_id FROM users WHERE id = auth.uid()))
);


-- USER UPDATE (Org Admins Editing Staff)
CREATE POLICY "Org Admins can update their staff"
ON users FOR UPDATE TO authenticated
USING (
  (SELECT role FROM users WHERE id = auth.uid()) IN ('organization', 'manager')
  AND 
  organization_id = (SELECT organization_id FROM users WHERE id = auth.uid())
);
