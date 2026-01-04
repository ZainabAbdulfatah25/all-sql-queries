-- ============================================================================
-- PERMANENT SYSTEM RULES (TRIGGERS)
-- Purpose: 
-- 1. Auto-Sync Users: Trigger on auth.users -> public.users (Immediate visibility).
-- 2. Auto-Log Activity: Triggers on tables -> activity_logs (Guaranteed history).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PERMANENT USER SYNC (Auth -> Public)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, name, role, organization_id, organization_name, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'role', 'viewer'),
    (NEW.raw_user_meta_data->>'organization_id')::uuid, -- Attempt to link Org ID if known
    COALESCE(NEW.raw_user_meta_data->>'organization_name', 'Defensera'), -- Default to Defensera if unknown
    NEW.created_at,
    NEW.created_at
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    updated_at = now();
  RETURN NEW;
END;
$$;

-- Trigger: Fires on every Signup/Invite (INSERT) and Update
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT OR UPDATE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ----------------------------------------------------------------------------
-- 2. PERMANENT ACTIVITY LOGGING (Database Level)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_activity_automatically()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_action TEXT;
  v_module TEXT;
  v_details TEXT;
BEGIN
  -- Determine User
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN 
     -- Use the 'created_by' field if auth.uid() is missing (e.g. system ops)
     BEGIN
        v_user_id := NEW.created_by;
     EXCEPTION WHEN OTHERS THEN NULL;
     END;
  END IF;

  -- Determine Action
  IF (TG_OP = 'INSERT') THEN
    v_action := 'create';
  ELSIF (TG_OP = 'UPDATE') THEN
    v_action := 'update';
  ELSIF (TG_OP = 'DELETE') THEN
    v_action := 'delete';
  END IF;

  -- Determine Module & Details based on Table
  IF (TG_TABLE_NAME = 'registrations') THEN
    v_module := 'beneficiaries';
    v_details := 'Beneficiary: ' || COALESCE(NEW.full_name, 'Unknown');
  ELSIF (TG_TABLE_NAME = 'cases') THEN
    v_module := 'cases';
    v_details := 'Case: ' || COALESCE(NEW.title, 'Unknown');
  ELSIF (TG_TABLE_NAME = 'referrals') THEN
    v_module := 'referrals';
    v_details := 'Referral: ' || COALESCE(NEW.client_name, 'Client');
  ELSE
    v_module := TG_TABLE_NAME;
    v_details := 'Item ID: ' || NEW.id;
  END IF;

  -- Insert Log (Safe Insert)
  IF v_user_id IS NOT NULL THEN
    INSERT INTO activity_logs (user_id, action, module, description, resource_id, created_at)
    VALUES (v_user_id, v_action, v_module, v_details, NEW.id::text, now());
  END IF;

  RETURN NULL; -- Result is ignored for AFTER triggers
END;
$$;

-- Apply Triggers
DROP TRIGGER IF EXISTS log_registrations_change ON registrations;
CREATE TRIGGER log_registrations_change
  AFTER INSERT OR UPDATE ON registrations
  FOR EACH ROW EXECUTE FUNCTION log_activity_automatically();

DROP TRIGGER IF EXISTS log_cases_change ON cases;
CREATE TRIGGER log_cases_change
  AFTER INSERT OR UPDATE ON cases
  FOR EACH ROW EXECUTE FUNCTION log_activity_automatically();

DROP TRIGGER IF EXISTS log_referrals_change ON referrals;
CREATE TRIGGER log_referrals_change
  AFTER INSERT OR UPDATE ON referrals
  FOR EACH ROW EXECUTE FUNCTION log_activity_automatically();
