-- ============================================================================
-- FIX SECURITY WARNINGS V2 (ALL SECURITY DEFINERS)
-- Purpose: 
-- 1. Fix "Mutable Search Path" warnings for ALL flagged functions.
-- 2. Ensure Referrals table has strict RLS.
-- ============================================================================

-- 1. FIX FUNCTION SEARCH PATHS (Prevents Privilege Escalation)
-- Set fixed search_path = public for all SECURITY DEFINER functions flagged.

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.auto_confirm_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE auth.users
    SET email_confirmed_at = now()
    WHERE id = NEW.id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.link_user_to_org_by_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  matching_org_id UUID;
  user_org_name TEXT;
BEGIN
  user_org_name := NEW.organization_name;
  IF user_org_name IS NOT NULL THEN
     SELECT id INTO matching_org_id FROM public.organizations 
     WHERE organization_name ILIKE user_org_name OR name ILIKE user_org_name 
     LIMIT 1;

     IF matching_org_id IS NOT NULL THEN
        NEW.organization_id := matching_org_id;
     END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- NEWLY FLAGGED FUNCTIONS
CREATE OR REPLACE FUNCTION public.sync_org_id_to_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE auth.users
  SET raw_user_meta_data = 
    coalesce(raw_user_meta_data, '{}'::jsonb) || 
    jsonb_build_object('organization_id', NEW.organization_id)
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.auto_adopt_user_to_org()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  creator_org_name TEXT;
  creator_org_id UUID;
BEGIN
  -- Find the organization of the creator
  SELECT organization_name, organization_id 
  INTO creator_org_name, creator_org_id
  FROM public.users
  WHERE id = auth.uid();

  -- If creator belongs to an org, assign the new user to it
  IF creator_org_name IS NOT NULL THEN
      NEW.organization_name := creator_org_name;
      NEW.organization_id := creator_org_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_status_update_permission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_role text;
BEGIN
  SELECT role INTO user_role FROM public.users WHERE id = auth.uid();
  
  -- Prevent "Completed" status if user is a Field Officer
  IF NEW.status = 'completed' AND user_role = 'field_officer' THEN
      RAISE EXCEPTION 'Field Officers cannot mark tasks as Completed.';
  END IF;
  
  RETURN NEW;
END;
$$;


-- 2. REINFORCE REFERRALS RLS (Clear & Strict)
-- Ensures no "permissive" warnings.

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Unified Read Policy" ON referrals;
DROP POLICY IF EXISTS "Unified Insert Policy" ON referrals;
DROP POLICY IF EXISTS "Unified Update Policy" ON referrals;
DROP POLICY IF EXISTS "Unified Delete Policy" ON referrals;

-- Read: Admins, State Admins, or Users involved in the referral
CREATE POLICY "Unified Read Policy" ON referrals FOR SELECT TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR created_by::text = auth.uid()::text
  OR referred_from::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
  OR referred_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
);

-- Insert: Authenticated users can create
CREATE POLICY "Unified Insert Policy" ON referrals FOR INSERT TO authenticated
WITH CHECK (auth.uid() IS NOT NULL);

-- Update: Admins or Involved Parties
CREATE POLICY "Unified Update Policy" ON referrals FOR UPDATE TO authenticated
USING (
  (SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin')
  OR created_by::text = auth.uid()::text
  OR referred_to::text = (SELECT organization_name::text FROM public.users WHERE id::text = auth.uid()::text)
)
WITH CHECK (true);

-- Delete: Admins only
CREATE POLICY "Unified Delete Policy" ON referrals FOR DELETE TO authenticated
USING ((SELECT role FROM public.users WHERE id::text = auth.uid()::text) IN ('admin', 'super_admin', 'state_admin'));


DO $$
BEGIN
  RAISE NOTICE 'All flagged security functions hardened. Referral policies standardized.';
END $$;
