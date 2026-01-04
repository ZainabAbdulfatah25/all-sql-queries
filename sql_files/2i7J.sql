-- ============================================================================
-- FIX ZAINAB SALMAN PERMISSIONS & DATA
-- Purpose:
-- 1. Promote 'zainabsalman' to Admin (so she can see system-wide activity).
-- 2. Ensure Activity Logs are populated.
-- ============================================================================

BEGIN;

-- 1. PROMOTE USER TO ADMIN
DO $$
DECLARE
  v_count INT;
BEGIN
  -- Update Public Profile
  UPDATE public.users 
  SET role = 'admin'
  WHERE email ILIKE 'zainabsalman%';

  -- Update Auth Metadata
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    '"admin"'
  )
  WHERE email ILIKE 'zainabsalman%';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Promoted % users matching "zainabsalman" to Admin.', v_count;
END $$;


-- 2. ENSURE ACTIVITY LOGS ARE POPULATED (Re-run Backfill)
-- Uses "ON CONFLICT" logic via NOT EXISTS check to avoid duplicates

-- A. Registrations
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 'create', 'beneficiaries', 'Registered beneficiary: ' || full_name, created_at, id::text
FROM registrations
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = registrations.created_by)
AND NOT EXISTS (SELECT 1 FROM activity_logs WHERE resource_id = registrations.id::text AND action = 'create');

-- B. Cases
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 'create', 'cases', 'Opened case: ' || title, created_at, id::text
FROM cases
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = cases.created_by)
AND NOT EXISTS (SELECT 1 FROM activity_logs WHERE resource_id = cases.id::text AND action = 'create');

-- C. Referrals
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 'create', 'referrals', 'Sent referral for: ' || COALESCE(client_name, 'Client'), created_at, id::text
FROM referrals
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = referrals.created_by)
AND NOT EXISTS (SELECT 1 FROM activity_logs WHERE resource_id = referrals.id::text AND action = 'create');

COMMIT;
