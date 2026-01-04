-- ============================================================================
-- UNIVERSAL ADOPTION RULES (SELF-HEALING)
-- Purpose: 
-- 1. If a user sets an 'organization_name', ensure that Org exists (Auto-Create).
-- 2. Link the user to that Org ID automatically.
-- 3. Run this for ALL users now and in the future.
-- ============================================================================

-- 1. THE TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION auto_adopt_user_to_org()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  -- Only act if we have a Name but no ID (or ID is mismatch)
  IF NEW.organization_name IS NOT NULL AND NEW.organization_name <> '' THEN
    
    -- A. Try to find existing Org
    SELECT id INTO v_org_id FROM organizations 
    WHERE name ILIKE NEW.organization_name OR organization_name ILIKE NEW.organization_name
    LIMIT 1;

    -- B. If not found, AUTO-CREATE IT
    IF v_org_id IS NULL THEN
      INSERT INTO organizations (name, organization_name, type, is_active, created_at, updated_at)
      VALUES (NEW.organization_name, NEW.organization_name, 'NGO', true, now(), now())
      RETURNING id INTO v_org_id;
      
      RAISE NOTICE 'Auto-Created Organization: %', NEW.organization_name;
    END IF;

    -- C. LINK THE USER
    NEW.organization_id := v_org_id;
    
  END IF;

  RETURN NEW;
END;
$$;


-- 2. INSTALL THE TRIGGER
DROP TRIGGER IF EXISTS universal_adoption_trigger ON users;

CREATE TRIGGER universal_adoption_trigger
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION auto_adopt_user_to_org();


-- 3. RETROACTIVE FIX (RUN ONCE FOR EXISTING DATA)
-- This forces the trigger to fire for every user, "healing" the whole database.
UPDATE users SET updated_at = now() WHERE organization_name IS NOT NULL;


-- 4. ENSURE ALL ROLES ARE VISIBLE (Admins see all)
-- (Reinforcing the robust visibility function from before)
CREATE OR REPLACE FUNCTION get_all_users()
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID;
  v_role TEXT;
  v_org_id UUID;
  v_org_name TEXT;
BEGIN
  v_uid := auth.uid();
  SELECT role, organization_id, organization_name INTO v_role, v_org_id, v_org_name 
  FROM users WHERE id = v_uid;

  IF v_role IN ('admin', 'state_admin', 'super_admin') THEN
     RETURN QUERY SELECT * FROM users ORDER BY created_at DESC;
  ELSIF v_org_id IS NOT NULL THEN
     RETURN QUERY SELECT * FROM users WHERE organization_id = v_org_id OR id = v_uid ORDER BY created_at DESC;
  ELSE
     -- Fallback for unlinked users: See anyone with same Org Name
     RETURN QUERY SELECT * FROM users WHERE organization_name ILIKE v_org_name OR id = v_uid ORDER BY created_at DESC;
  END IF;
END;
$$;


