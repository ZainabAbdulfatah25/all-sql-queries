-- ============================================================================
-- FIX ACTIVITY BACKFILL & RELATIONS
-- Purpose: 
-- 1. Fix Foreign Key to point to public.users (so frontend JOIN works).
-- 2. Retroactively create activity logs for existing Cases, Registrations, and Referrals.
-- ============================================================================

-- 1. FIX FOREIGN KEY (Point to public.users for 'user:users(name)' query)
ALTER TABLE activity_logs 
  DROP CONSTRAINT IF EXISTS activity_logs_user_id_fkey;

ALTER TABLE activity_logs
  ADD CONSTRAINT activity_logs_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 2. BACKFILL FROM REGISTRATIONS
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT 
  created_by, 
  'create', 
  'beneficiaries', 
  'Registered beneficiary: ' || full_name, 
  created_at, 
  id::text
FROM registrations
WHERE created_by IS NOT NULL;

-- 3. BACKFILL FROM CASES
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT 
  created_by, 
  'create', 
  'cases', 
  'Opened case: ' || title, 
  created_at, 
  id::text
FROM cases
WHERE created_by IS NOT NULL;

-- 4. BACKFILL FROM REFERRALS
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT 
  created_by, 
  'create', 
  'referrals', 
  'Sent referral for: ' || COALESCE(client_name, 'Client'), 
  created_at, 
  id::text
FROM referrals
WHERE created_by IS NOT NULL;

-- 5. RE-VERIFY INDEXES
CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at ON activity_logs(created_at DESC);
