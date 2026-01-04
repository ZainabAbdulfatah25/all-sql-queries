-- ============================================================================
-- PERMANENT USER RULES & RECOVERY
-- Purpose: 
-- 1. Create a "Rule" (Trigger) that AUTOMATICALLY links users to their Org ID.
-- 2. Recover "John Doe" who is currently invisible.
-- 3. Ensure Login works for everyone.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RULE 1: AUTO-LINK ORGANIZATION (Visibility Fix)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION link_user_to_org_by_name()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_org_id UUID;
BEGIN
  -- If ID is missing but Name is present, try to find the ID
  IF NEW.organization_id IS NULL AND NEW.organization_name IS NOT NULL THEN
    
    SELECT id INTO v_org_id FROM organizations 
    WHERE name ILIKE NEW.organization_name OR organization_name ILIKE NEW.organization_name
    LIMIT 1;

    IF v_org_id IS NOT NULL THEN
      NEW.organization_id := v_org_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop (if exists) and Re-create Trigger
DROP TRIGGER IF EXISTS ensure_org_link_trigger ON users;
CREATE TRIGGER ensure_org_link_trigger
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION link_user_to_org_by_name();


-- ----------------------------------------------------------------------------
-- RECOVERY: FIND JOHN DOE (And others)
-- ----------------------------------------------------------------------------
-- This explicitly fixes users who are "stuck" invisible right now.

DO $$
DECLARE
  v_defensera_id UUID;
BEGIN
  -- Get Defensera ID
  SELECT id INTO v_defensera_id FROM organizations WHERE name ILIKE 'Defensera' LIMIT 1;

  -- 1. Fix John Doe (by name or partial email)
  UPDATE users 
  SET organization_id = v_defensera_id, organization_name = 'Defensera'
  WHERE (name ILIKE '%john%' OR email ILIKE '%john%') 
  AND organization_id IS NULL;

  -- 2. Fix ANYONE ELSE with 'Defensera' name but no ID
  UPDATE users 
  SET organization_id = v_defensera_id
  WHERE organization_name ILIKE 'Defensera' AND organization_id IS NULL;

  RAISE NOTICE 'Recovered invisible users.';
END $$;


-- ----------------------------------------------------------------------------
-- RULE 2: ENSURE LOGIN ACCESS (Email Confirmation)
-- ----------------------------------------------------------------------------
-- Confirm everyone so they can log in immediately.
UPDATE auth.users SET email_confirmed_at = now() WHERE email_confirmed_at IS NULL;

RAISE NOTICE 'All email addresses confirmed for login.';
