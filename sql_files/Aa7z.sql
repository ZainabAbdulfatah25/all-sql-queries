-- ============================================================================
-- POPULATE ACTIVITY LOGS (MASTER FIX)
-- Purpose: 
-- 1. Ensure table and permissions exist.
-- 2. Backfill historical data from Cases, Registrations, Referrals.
-- 3. Ensure foreign keys point to public.users for frontend joins.
-- ============================================================================

-- 1. TABLE STRUCTURE & FOREIGN KEY
CREATE TABLE IF NOT EXISTS activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL, -- Will enforce FK below
  action TEXT NOT NULL,
  module TEXT NOT NULL,
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  device_id TEXT,
  resource_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Point FK to public.users (Crucial for user:users(name) join)
DO $$ BEGIN
  ALTER TABLE activity_logs 
    DROP CONSTRAINT IF EXISTS activity_logs_user_id_fkey;
  
  ALTER TABLE activity_logs
    ADD CONSTRAINT activity_logs_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;


-- 2. ENABLE RLS & POLICIES
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Activity Logs Select" ON activity_logs;
CREATE POLICY "Activity Logs Select"
ON activity_logs FOR SELECT TO authenticated
USING (
  -- Global Admins see all
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- Org Managers see their org
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
       SELECT 1 FROM public.users u
       WHERE u.id = activity_logs.user_id
       AND u.organization_id = get_auth_user_org_id()
    )
  )
  OR
  -- Users see self
  user_id = auth.uid()
);

DROP POLICY IF EXISTS "Activity Logs Insert" ON activity_logs;
CREATE POLICY "Activity Logs Insert"
ON activity_logs FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());


-- 3. BACKFILL DATA (Idempotent)
-- We use DISTINCT to avoid duplicates if run multiple times based on resource_id + action

-- A. From Registrations
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 
  'create', 
  'beneficiaries', 
  'Registered beneficiary: ' || full_name, 
  created_at, 
  id::text
FROM registrations
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = registrations.created_by)
AND NOT EXISTS (
    SELECT 1 FROM activity_logs 
    WHERE resource_id = registrations.id::text AND action = 'create'
);

-- B. From Cases
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 
  'create', 
  'cases', 
  'Opened case: ' || title, 
  created_at, 
  id::text
FROM cases
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = cases.created_by)
AND NOT EXISTS (
    SELECT 1 FROM activity_logs 
    WHERE resource_id = cases.id::text AND action = 'create'
);

-- C. From Referrals
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 
  'create', 
  'referrals', 
  'Sent referral for: ' || COALESCE(client_name, 'Client'), 
  created_at, 
  id::text
FROM referrals
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = referrals.created_by)
AND NOT EXISTS (
    SELECT 1 FROM activity_logs 
    WHERE resource_id = referrals.id::text AND action = 'create'
);

-- 4. VERIFY
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM activity_logs;
  RAISE NOTICE 'Total Activity Logs: %', v_count;
END $$;
