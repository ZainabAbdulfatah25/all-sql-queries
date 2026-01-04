-- ============================================================================
-- ENFORCE STRICT PRIVACY GLOBALLY
-- Purpose: 
-- 1. Scrub invalid roles (Individuals cannot be 'organization' or 'manager').
-- 2. Force Sync ALL Metadata (Ensure JWTs will be correct).
-- 3. Lock down RLS (Paranoid Mode).
-- ============================================================================

-- A. ROLE SCRUBBING (Data Cleanup)
DO $$
BEGIN
  -- 1. Downgrade any 'organization' or 'manager' who has NO Organization
  UPDATE public.users 
  SET role = 'case_worker'
  WHERE organization_id IS NULL 
  AND role IN ('organization', 'manager');
  
  -- 2. Downgrade 'viewer' to 'case_worker' so they can at least register
  UPDATE public.users
  SET role = 'case_worker'
  WHERE role = 'viewer';

END $$;


-- B. METADATA FUSH (Force Sync to Auth)
-- This ensures that when they login, their token has the CORRECT role.
DO $$ 
BEGIN
  UPDATE auth.users u
  SET raw_user_meta_data = 
    COALESCE(u.raw_user_meta_data, '{}'::jsonb) || 
    jsonb_build_object(
      'role', p.role, 
      'organization_id', p.organization_id
    )
  FROM public.users p
  WHERE u.id = p.id;
END $$;


-- C. PARANOID RLS (Registrations)
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- 1. SUPER ADMINS (The only ones who see everything unconditionally)
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATION STAFF (Strict Check)
  (
    -- Must have specific role AND have an Org ID
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    get_auth_user_org_id() IS NOT NULL
    AND
    -- The record must belong to someone in SAME Org
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )

  OR

  -- 3. DEFAULT: VIEW OWN ONLY (Everyone else)
  (
     created_by = auth.uid()
  )
);

-- D. INSERT POLICY (Strict)
DROP POLICY IF EXISTS "Beneficiaries Insert" ON registrations;
CREATE POLICY "Beneficiaries Insert"
ON registrations FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
);

-- E. UPDATE POLICY (Strict)
DROP POLICY IF EXISTS "Beneficiaries Update" ON registrations;
CREATE POLICY "Beneficiaries Update"
ON registrations FOR UPDATE TO authenticated
USING (
  -- Admin
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- Owner
  created_by = auth.uid()
  OR
  -- Org Manager (Can update status etc)
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    get_auth_user_org_id() IS NOT NULL
    AND
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )
);

-- F. DELETE POLICY (Strict Owner Only + Admin)
DROP POLICY IF EXISTS "Beneficiaries Delete" ON registrations;
CREATE POLICY "Beneficiaries Delete"
ON registrations FOR DELETE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  created_by = auth.uid()
);
