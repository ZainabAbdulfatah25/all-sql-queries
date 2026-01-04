-- Check counts
DO $$
DECLARE
    log_count integer;
    user_count integer;
BEGIN
    SELECT count(*) INTO log_count FROM activity_logs;
    SELECT count(*) INTO user_count FROM users;
    RAISE NOTICE 'Activity Logs Count: %, Users Count: %', log_count, user_count;
END $$;

-- Fix RLS for Reporting
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Allow reading all users for reporting (authenticated users)
DROP POLICY IF EXISTS "Allow read access to all users" ON users;
CREATE POLICY "Allow read access to all users" ON users FOR SELECT USING (auth.role() = 'authenticated');

-- Allow reading all activity logs for reporting (authenticated users or at least admins)
-- For now, allow authenticated to read all to debug "blank report"
DROP POLICY IF EXISTS "Allow read access to all activity logs" ON activity_logs;
CREATE POLICY "Allow read access to all activity logs" ON activity_logs FOR SELECT USING (auth.role() = 'authenticated');

-- Verify join accessibility
-- The API uses: .select('*, user:users(name, email)')
-- This requires access to public.users table (which is what we just patched).
