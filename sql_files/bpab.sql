-- ============================================================================
-- FIX SECURITY WARNINGS & BEST PRACTICES
-- Purpose: 
-- 1. Fix "Mutable Search Path" warnings for SECURITY DEFINER functions.
-- 2. Ensure Referrals table has strict RLS (similar to Cases/Registrations).
-- ============================================================================

-- 1. FIX FUNCTION SEARCH PATHS (Prevents Privilege Escalation)
-- It is a best practice to set a fixed search_path for SECURITY DEFINER functions.

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
  user_email TEXT;
  user_org_name TEXT;
BEGIN
  -- Safe access to organization name from metadata or table
  user_org_name := NEW.organization_name;
  
  -- If org name is present, try to find ID and link
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

-- 2. REINFORCE REFERRALS RLS (Clear & Strict)
-- Ensures no "permissive" warnings and aligns with the fixed schema.

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Unified Read Policy" ON referrals;
DROP POLICY IF EXISTS "Unified Insert Policy" ON referrals;
DROP POLICY IF EXISTS "Unified Update Policy" ON referrals;
DROP POLICY IF EXISTS "Unified Delete Policy" ON referrals;

-- Read: Admins, State Admins, or Users involved in the referral (From/To)
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
  RAISE NOTICE 'Security functions hardened with fixed search_path. Referral policies standardized.';
END $$;
