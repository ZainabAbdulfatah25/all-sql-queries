-- ============================================================================
-- FIX LOGIN CRASH (METADATA SYNC SOLUTION)
-- Purpose: Stop RLS Infinite Recursion by moving 'organization_id' check 
--          from Table Query -> JWT Metadata.
-- ============================================================================

-- 1. SYNC EXISTING DATA (Public Users -> Auth Metadata)
DO $$ 
BEGIN
  UPDATE auth.users u
  SET raw_user_meta_data = 
    COALESCE(u.raw_user_meta_data, '{}'::jsonb) || 
    jsonb_build_object('organization_id', p.organization_id)
  FROM public.users p
  WHERE u.id = p.id 
  AND p.organization_id IS NOT NULL;
  
  RAISE NOTICE 'Organization IDs synced to Auth Metadata.';
END $$;


-- 2. CREATE SYNC TRIGGER (Keep Metadata Fresh)
CREATE OR REPLACE FUNCTION sync_org_id_to_metadata()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    UPDATE auth.users
    SET raw_user_meta_data = 
      COALESCE(raw_user_meta_data, '{}'::jsonb) || 
      jsonb_build_object('organization_id', NEW.organization_id)
    WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS sync_org_id_meta_trigger ON users;
CREATE TRIGGER sync_org_id_meta_trigger
AFTER INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION sync_org_id_to_metadata(); 

