-- ============================================================================
-- FIX PRIVACY FINAL MEASURES (The "Nuclear" Purge)
-- Purpose: 
-- 1. Dynamically DROP EVERY POLICY on 'registrations' (prevents ghost policies).
-- 2. Set Default Role to 'case_worker' (so new users are safe by default).
-- 3. Re-apply Strict RLS.
-- ============================================================================

-- A. DYNAMIC POLICY PURGE
-- This loops through the system catalog and deletes any policy attached to 'registrations'.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'registrations' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON registrations', r.policyname);
    RAISE NOTICE 'Dropped policy: %', r.policyname;
  END LOOP;
END $$;


-- B. LOCK DOWN SCHEMA DEFAULTS
-- Ensure that if the frontend sends nothing, the DB chooses "Safe Individual".
ALTER TABLE public.users ALTER COLUMN role SET DEFAULT 'case_worker';
ALTER TABLE public.users ALTER COLUMN organization_id SET DEFAULT NULL;


-- C. RE-APPLY STRICT RLS (The Only Policy Allowed)
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- 1. ADMINS
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATIONS (Strict Live Check)
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
       SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
       AND u.organization_id IS NOT NULL
       -- Matches record creator's org
       AND u.organization_id = (SELECT c.organization_id FROM users c WHERE c.id = registrations.created_by)
    )
  )

  OR

  -- 3. INDIVIDUALS / EVERYONE ELSE (Own Data Only)
  (
     created_by = auth.uid()
  )
);

-- D. INSERT/UPDATE/DELETE (Strict)
CREATE POLICY "Beneficiaries Insert" ON registrations FOR INSERT TO authenticated
WITH CHECK ( created_by = auth.uid() );

CREATE POLICY "Beneficiaries Update" ON registrations FOR UPDATE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin') OR
  created_by = auth.uid() OR
  (get_auth_user_role() IN ('organization', 'manager') AND get_auth_user_org_id() IS NOT NULL)
);

CREATE POLICY "Beneficiaries Delete" ON registrations FOR DELETE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin') OR
  created_by = auth.uid()
);


-- E. FIX ZAINAB SALMAN (Specific)
DO $$
DECLARE
  v_email text := 'zainabsalman@example.com'; -- Adjusted based on screenshot prompt, check spelling
BEGIN
  UPDATE public.users 
  SET organization_id = NULL, role = 'case_worker'
  WHERE email LIKE 'zainabsalman%';

  UPDATE auth.users
  SET raw_user_meta_data = jsonb_build_object('role', 'case_worker', 'organization_id', NULL)
  WHERE email LIKE 'zainabsalman%';
END $$;
