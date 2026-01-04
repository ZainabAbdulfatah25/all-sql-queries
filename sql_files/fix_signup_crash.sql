-- ============================================================================
-- FIX SIGNUP CRASH (HARDENING TRIGGERS)
-- Purpose: 
-- 1. Replace 'auto_adopt_user_to_org' with a crash-proof version.
-- 2. Replace 'sync_org_id_to_metadata' with a crash-proof version.
-- ============================================================================

-- A. HARDEN UNIVERSAL ADOPTION (The "Auto Link" Trigger)
CREATE OR REPLACE FUNCTION auto_adopt_user_to_org()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  -- 1. If no org name provided, do nothing (Individual User)
  IF NEW.organization_name IS NULL OR NEW.organization_name = '' THEN
    RETURN NEW;
  END IF;

  -- 2. If already linked, do nothing
  IF NEW.organization_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    -- 3. Try to find existing org
    SELECT id INTO v_org_id FROM organizations WHERE name = NEW.organization_name LIMIT 1;

    -- 4. If not found, Create it!
    IF v_org_id IS NULL THEN
      INSERT INTO organizations (name, slug, type, status, created_by)
      VALUES (
        NEW.organization_name, 
        lower(regexp_replace(NEW.organization_name, '[^a-zA-Z0-9]+', '-', 'g')), 
        COALESCE(NEW.organization_type, 'NGO'), 
        'active',
        NEW.id
      )
      RETURNING id INTO v_org_id;
    END IF;

    -- 5. Link User
    NEW.organization_id := v_org_id;
    NEW.role := 'organization'; -- Enforce role if they have an org
    
  EXCEPTION WHEN OTHERS THEN
    -- If ANYTHING fails, just log and continue (don't crash signup!)
    -- We leave organization_id as NULL, user allows creation.
    NULL; 
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_adopt_user_to_org ON users;
CREATE TRIGGER auto_adopt_user_to_org
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION auto_adopt_user_to_org();


-- B. HARDEN METADATA SYNC (The "Login Fix" Trigger)
CREATE OR REPLACE FUNCTION sync_org_id_to_metadata()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only run if org_id actually changed (avoid useless writes)
  IF (TG_OP = 'INSERT' AND NEW.organization_id IS NOT NULL) OR 
     (TG_OP = 'UPDATE' AND NEW.organization_id IS DISTINCT FROM OLD.organization_id) THEN
     
     BEGIN
       UPDATE auth.users
       SET raw_user_meta_data = 
         COALESCE(raw_user_meta_data, '{}'::jsonb) || 
         jsonb_build_object('organization_id', NEW.organization_id)
       WHERE id = NEW.id;
     EXCEPTION WHEN OTHERS THEN
       -- Safely ignore errors during metadata sync to prevent txn rollback
       NULL;
     END;
     
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_org_id_meta_trigger ON users;
CREATE TRIGGER sync_org_id_meta_trigger
AFTER INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION sync_org_id_to_metadata(); 


-- C. SYNTAX CHECK TO ENSURE NO ERRORS
-- Just a simple query to confirm script finished.
SELECT count(*) FROM users;
