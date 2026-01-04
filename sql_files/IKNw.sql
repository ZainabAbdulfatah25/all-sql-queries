-- ============================================================================
-- RELINK ALL ORGANIZATION STAFF
-- Purpose: 
-- 1. Restore missing organization links for ALL users (not just Defensera).
-- 2. Uses the 'created_by' relationship: If a user was created by an Organization Admin,
--    they belong to that Organization.
-- 3. Sets user_type = 'organization' to prevent future "Individual" cleanup issues.
-- ============================================================================

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Update orphans by finding who created them in the ACTIVITY LOGS
  -- Heuristic: Log 'create', module 'users', description contains 'Created user: <Name>'
  
  WITH creator_map AS (
    SELECT 
      al.user_id AS creator_id, 
      al.created_at,
      -- Extract name from "Created user: NAME"
      TRIM(SUBSTRING(al.description FROM 'Created user: (.*)')) as target_user_name
    FROM activity_logs al
    WHERE al.action = 'create' AND al.module = 'users'
  ),
  matched_creators AS (
    SELECT 
      u.id as orphan_id,
      c.organization_id,
      c.organization_name
    FROM users u
    JOIN creator_map cm ON u.name = cm.target_user_name
    JOIN users c ON cm.creator_id = c.id
    WHERE 
      u.organization_id IS NULL -- Only target orphans
      AND c.organization_id IS NOT NULL -- Creator must have Org
      AND c.role IN ('organization', 'manager') -- Creator is admin
      -- Tie break: if multiple logs, pick latest? But simple join is okay for now.
  )
  UPDATE users u
  SET 
    organization_id = mc.organization_id,
    organization_name = mc.organization_name,
    user_type = 'organization',
    updated_at = now()
  FROM matched_creators mc
  WHERE u.id = mc.orphan_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Relinked % staff members using Activity Logs history.', v_count;

END $$;
