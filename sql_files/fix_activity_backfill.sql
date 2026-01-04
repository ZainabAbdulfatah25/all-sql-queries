-- ============================================================================
-- FIX ACTIVITY BACKFILL (Safe Version)
-- Purpose: 
-- 1. Fix Foreign Key to point to public.users.
-- 2. Retroactively create activity logs for existing records.
-- 3. SKIP records created by deleted users (Orphans) to avoid FK errors.
-- ============================================================================

-- 1. FIX FOREIGN KEY (Point to public.users for 'user:users(name)' query)
ALTER TABLE activity_logs 
  DROP CONSTRAINT IF EXISTS activity_logs_user_id_fkey;

ALTER TABLE activity_logs
  ADD CONSTRAINT activity_logs_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 2. BACKFILL FROM REGISTRATIONS (Only if user exists)
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT 
  created_by, 
  'create', 
  'beneficiaries', 
  'Registered beneficiary: ' || full_name, 
  created_at, 
  id::text
FROM registrations
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = registrations.created_by);

-- 3. BACKFILL FROM CASES (Only if user exists)
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT 
  created_by, 
  'create', 
  'cases', 
  'Opened case: ' || title, 
  created_at, 
  id::text
FROM cases
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = cases.created_by);

-- 4. BACKFILL FROM REFERRALS (Only if user exists)
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT 
  created_by, 
  'create', 
  'referrals', 
  'Sent referral for: ' || COALESCE(client_name, 'Client'), 
  created_at, 
  id::text
FROM referrals
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = referrals.created_by);

-- 5. RE-VERIFY INDEXES
CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at ON activity_logs(created_at DESC);
