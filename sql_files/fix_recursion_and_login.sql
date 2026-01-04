-- ============================================================================
-- FIX RECURSION & LOGIN CRASH
-- Purpose: 
-- 1. Break the infinite loop between auth.users and public.users triggers.
-- 2. Optimize user sync to only update when necessary.
-- ============================================================================

-- 1. FIX THE TRIGGER CAUSING RECURSION (Public -> Auth)
-- This function was blindly updating auth.users, causing the loop.
-- We add a check to ONLY update if organization_id actually changed.

CREATE OR REPLACE FUNCTION public.sync_org_id_to_metadata()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- BREAK RECURSION: Only update if organization_id IS DISTINCT
  IF (TG_OP = 'INSERT') OR (NEW.organization_id IS DISTINCT FROM OLD.organization_id) THEN
    
    UPDATE auth.users
    SET raw_user_meta_data = 
      COALESCE(raw_user_meta_data, '{}'::jsonb) || 
      jsonb_build_object('organization_id', NEW.organization_id)
    WHERE id = NEW.id;
    
  END IF;

  RETURN NEW;
END;
$$;

-- Ensure trigger is correctly applied
DROP TRIGGER IF EXISTS sync_org_id_meta_trigger ON users;
CREATE TRIGGER sync_org_id_meta_trigger
AFTER INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION sync_org_id_to_metadata(); 


-- 2. OPTIMIZE AUTH SYNC (Auth -> Public)
-- Prevent unnecessary updates to public.users on every login (which updates last_sign_in_at)
-- if no relevant fields (metadata/email) changed.

CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_org_name TEXT;
  v_name TEXT;
  v_role TEXT;
BEGIN
  -- Extract Values
  v_name := COALESCE(NEW.raw_user_meta_data->>'name', NEW.email);
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'viewer');
  v_org_id := (NEW.raw_user_meta_data->>'organization_id')::uuid;
  v_org_name := COALESCE(NEW.raw_user_meta_data->>'organization_name', 'Defensera');

  -- Insert or Update
  INSERT INTO public.users (id, email, name, role, organization_id, organization_name, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.email,
    v_name,
    v_role,
    v_org_id,
    v_org_name,
    NEW.created_at,
    NEW.created_at -- updated_at same as created_at on insert
  )
  ON CONFLICT (id) DO UPDATE SET
    -- ONLY update if these fields are different (Optimization)
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    updated_at = now()
  WHERE 
    users.email IS DISTINCT FROM EXCLUDED.email OR
    users.name IS DISTINCT FROM EXCLUDED.name OR
    users.role IS DISTINCT FROM EXCLUDED.role;
    
  RETURN NEW;
END;
$$;


DO $$
BEGIN
  RAISE NOTICE 'Recursion loop broken. Login triggers optimized.';
END $$;
