/*
  # Remove unused indexes

  ## Changes
  
  Remove indexes that are not being used by queries to reduce
  storage overhead and improve write performance.
*/

-- Remove unused indexes (but keep those that might be used in future queries)
-- Keep approval_status indexes as they may be used for filtering
-- Keep created_at as it's used for ordering
-- Remove truly unused ones

DROP INDEX IF EXISTS idx_users_language;
DROP INDEX IF EXISTS idx_organizations_type;
DROP INDEX IF EXISTS idx_activity_logs_resource;

-- Note: We're keeping the following indexes even though currently unused,
-- as they are likely to be used in common query patterns:
-- - idx_cases_approval_status (for filtering approved cases)
-- - idx_registrations_approval_status (for filtering approved registrations)
-- - idx_referrals_approval_status (for filtering approved referrals)
-- - idx_registrations_status (for filtering by status)
-- - idx_cases_created_at (for ordering/date range queries)
-- - idx_registrations_qr_code (for QR code lookups)
-- - idx_activity_logs_user_id (for user activity queries)
-- - idx_household_members_registration_id (for family member lookups)
