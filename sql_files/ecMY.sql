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
AFTER UPDATE OR JOIN ON users
FOR EACH ROW
EXECUTE FUNCTION sync_org_id_to_metadata(); 
-- Note: triggers on INSERT too if we used proper syntax, but keeping simple.
-- Let's fix syntax:
DROP TRIGGER IF EXISTS sync_org_id_meta_trigger_insert ON users;
CREATE TRIGGER sync_org_id_meta_trigger_insert
AFTER INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION sync_org_id_to_metadata();


-- 3. REWRITE HELPER FUNCTIONS (RECURSION FREE)

-- Safe Role Check (Already good, but reinforcing)
CREATE OR REPLACE FUNCTION get_auth_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN COALESCE(
    current_setting('request.jwt.claims', true)::jsonb->'user_metadata'->>'role',
    'viewer'
  );
END;
$$;

-- Safe Org ID Check (READS METADATA NOW, NOT TABLE)
CREATE OR REPLACE FUNCTION get_auth_user_org_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_meta_id text;
BEGIN
  v_meta_id := current_setting('request.jwt.claims', true)::jsonb->'user_metadata'->>'organization_id';
  
  -- Handle empty/null case
  IF v_meta_id IS NULL OR v_meta_id = '' THEN
    RETURN NULL;
  END IF;

  RETURN v_meta_id::UUID;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL; -- Fail safe
END;
$$;


-- 4. RE-APPLY USERS RLS (Now Safe)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view relevant profiles" ON users;
DROP POLICY IF EXISTS "Users Visibility" ON users; -- Cleanup old names

CREATE POLICY "Users Visibility"
ON users FOR SELECT TO authenticated
USING (
  -- Admin sees all
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  OR
  -- Users see themselves
  id = auth.uid()
  OR
  -- Users see colleagues (SAFE NOW because get_auth_user_org_id() is pure JWT)
  (organization_id IS NOT NULL AND organization_id = get_auth_user_org_id())
);

RAISE NOTICE 'Login Crash Fixed. Recursion Loop Broken.';
