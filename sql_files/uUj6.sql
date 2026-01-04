-- ============================================================================
-- FIX DATA INTEGRITY: Link Users to Organizations
-- Purpose: Ensure all users have the correct organization_id based on their organization_name.
--          This fixes RLS visibility issues.
-- ============================================================================

DO $$
BEGIN
  -- 1. Update users who have an organization_name but no organization_id
  --    Match against 'organizations.name' or 'organizations.organization_name'
  UPDATE users u
  SET organization_id = o.id
  FROM organizations o
  WHERE u.organization_id IS NULL
  AND u.organization_name IS NOT NULL
  AND (
    u.organization_name ILIKE o.name 
    OR 
    u.organization_name ILIKE o.organization_name
  );
  
  -- 2. Explicit fix for the reporting user if needed
  --    (Matches Defensera specifically if typical match failed due to typos)
  UPDATE users
  SET organization_id = (SELECT id FROM organizations WHERE name ILIKE 'Defensera' OR organization_name ILIKE 'Defensera' LIMIT 1)
  WHERE email = 'abdulfatahzainab3@gmail.com'
  AND organization_id IS NULL;

  -- 3. Also fix children users created by this admin if they are still null
  --    (If the admin was fixed above, we might need to re-run or just fix by name again)
  --    The first query should cover most cases.

END $$;
