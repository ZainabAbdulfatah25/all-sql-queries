-- ============================================================================
-- INHERIT DEPARTMENT FROM CREATOR
-- Purpose: 
-- 1. "Do the same fix" for Departments: Ensure staff display a department.
-- 2. If a user has NO department, we assume they belong to the same department as the Admin who created them.
-- ============================================================================

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Update orphans by finding who created them (using Activity Logs logic if needed, or direct created_by if available)
  -- Since we established 'created_by' column doesn't exist, we MUST use the Activity Logs method again.
  
  WITH creator_map AS (
    SELECT 
      al.user_id AS creator_id, 
      al.created_at,
      TRIM(SUBSTRING(al.description FROM 'Created user: (.*)')) as target_user_name
    FROM activity_logs al
    WHERE al.action = 'create' AND al.module = 'users'
  ),
  matched_creators AS (
    SELECT 
      u.id as orphan_id,
      c.department as creator_department
    FROM users u
    JOIN creator_map cm ON u.name = cm.target_user_name
    JOIN users c ON cm.creator_id = c.id
    WHERE 
      u.department IS NULL -- Only target users with NO department
      AND c.department IS NOT NULL -- Creator must have a department
      AND c.role IN ('organization', 'manager', 'admin') -- Creator is likely an admin
  )
  UPDATE users u
  SET 
    department = mc.creator_department,
    updated_at = now()
  FROM matched_creators mc
  WHERE u.id = mc.orphan_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Updated % staff members to inherit department from their creator.', v_count;

END $$;
