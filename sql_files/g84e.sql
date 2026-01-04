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
  -- Update orphans based on who created them
  UPDATE users u
  SET 
    organization_id = creator.organization_id,
    organization_name = creator.organization_name,
    user_type = 'organization',
    updated_at = now()
  FROM users creator
  WHERE 
    u.created_by = creator.id
    AND u.organization_id IS NULL             -- Target only users missing an org
    AND creator.organization_id IS NOT NULL   -- Creator must have an org
    AND creator.role IN ('organization', 'manager') -- Creator must be an Org Admin/Manager
    AND u.role NOT IN ('admin', 'state_admin', 'super_admin'); -- Don't touch system admins

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Relinked % staff members to their organizations based on creator.', v_count;

END $$;
