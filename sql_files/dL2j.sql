-- ============================================================================
-- FIX ACTIVITY LOGS PERMISSIONS
-- Purpose: 
-- 1. Ensure 'activity_logs' has RLS enabled.
-- 2. Allow ALL authenticated users to INSERT logs (for themselves).
-- 3. Allow Admins to VIEW all logs.
-- 4. Allow Org Managers to VIEW logs from their org members.
-- 5. Allow Individuals to VIEW their own logs.
-- ============================================================================

-- 1. Enable RLS
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON activity_logs;
DROP POLICY IF EXISTS "Enable read access for all users" ON activity_logs;
DROP POLICY IF EXISTS "Activity Logs Select" ON activity_logs;
DROP POLICY IF EXISTS "Activity Logs Insert" ON activity_logs;

-- 3. INSERT POLICY: Everyone can log their own actions
CREATE POLICY "Activity Logs Insert"
ON activity_logs FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
);

-- 4. SELECT POLICY: Complex visibility rules
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
    -- Log belongs to a user who is in my Organization
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

-- 5. Fix Foreign Key (Just in case)
-- Ensure user_id actually references public.users(id)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'activity_logs_user_id_fkey') THEN
    ALTER TABLE activity_logs 
    ADD CONSTRAINT activity_logs_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;
