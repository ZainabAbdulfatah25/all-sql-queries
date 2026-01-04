-- ============================================================================
-- FIX ACTIVITY LOGS (Create Table + Permissions)
-- Purpose: 
-- 1. Create 'activity_logs' table if it doesn't exist.
-- 2. Enable RLS and set policies.
-- ============================================================================

-- 1. CREATE TABLE
CREATE TABLE IF NOT EXISTS activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- Use auth.users initially for safety
  action TEXT NOT NULL,
  module TEXT NOT NULL,
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  device_id TEXT,
  resource_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. ENABLE RLS
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

-- 3. CLEAN UP OLD POLICIES
DROP POLICY IF EXISTS "Activity Logs Insert" ON activity_logs;
DROP POLICY IF EXISTS "Activity Logs Select" ON activity_logs;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON activity_logs;
DROP POLICY IF EXISTS "Enable read access for all users" ON activity_logs;

-- 4. INSERT POLICY (Log Self)
CREATE POLICY "Activity Logs Insert"
ON activity_logs FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
);

-- 5. SELECT POLICY (Visibility)
CREATE POLICY "Activity Logs Select"
ON activity_logs FOR SELECT TO authenticated
USING (
  -- A. GLOBAL ADMINS
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- B. ORGANIZATION MANAGERS
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

  -- C. INDIVIDUALS / SELF
  (
     user_id = auth.uid()
  )
);

-- 6. INDEXES (for performance)
CREATE INDEX IF NOT EXISTS idx_activity_logs_user_id ON activity_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at ON activity_logs(created_at);
