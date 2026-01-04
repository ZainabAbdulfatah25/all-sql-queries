-- ============================================================================
-- FIX SECURITY ADVISOR ISSUES (FINAL)
-- Purpose:
-- 1. Fix "Function Search Path Mutable" for log_activity_automatically.
-- 2. Fix "RLS references user metadata" by redefining helper functions to use table lookups.
-- 3. Re-apply strict RLS on referrals to ensuring strictly table-based policies.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FIX MUTABLE SEARCH PATH (Warning #1)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_activity_automatically()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public -- FIX: specific search path
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
    INSERT INTO public.activity_logs (user_id, action, module, description, resource_id, created_at)
    VALUES (v_user_id, v_action, v_module, v_details, NEW.id::text, now());
  END IF;

  RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. FIX RLS REFERENCING METADATA (Error #1, #2, #3)
-- The advisor complains if RLS uses auth.jwt()->>'role' or user_metadata.
-- We redefine these helpers to look up the secure public.users table instead.
-- ----------------------------------------------------------------------------

-- Function: get_auth_role()
-- Replaced to query table instead of metadata.
CREATE OR REPLACE FUNCTION public.get_auth_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE -- Mark as stable for performance optimization in RLS
AS $$
BEGIN
  RETURN (
    SELECT role::text 
    FROM public.users 
    WHERE id = auth.uid()
  );
END;
$$;

-- Function: get_auth_org_id()
-- Replaced to query table instead of metadata.
CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  RETURN (
    SELECT organization_id 
    FROM public.users 
    WHERE id = auth.uid()
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. RE-APPLY STRICT RLS ON REFERRALS
-- Ensure no old policies are lingering that use insecure metadata.
-- ----------------------------------------------------------------------------
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- Drop ALL known potential policies to clean the slate
DROP POLICY IF EXISTS "Unified Read Policy" ON public.referrals;
DROP POLICY IF EXISTS "Unified Insert Policy" ON public.referrals;
DROP POLICY IF EXISTS "Unified Update Policy" ON public.referrals;
DROP POLICY IF EXISTS "Unified Delete Policy" ON public.referrals;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.referrals;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.referrals;
DROP POLICY IF EXISTS "Referrals are viewable by everyone" ON public.referrals;
DROP POLICY IF EXISTS "Referrals can be created by authenticated users" ON public.referrals;
-- Specifically identified problematic policies from user screenshot/legacy files:
DROP POLICY IF EXISTS "users_can_view_referrals" ON public.referrals;
DROP POLICY IF EXISTS "users_can_update_referrals" ON public.referrals;
DROP POLICY IF EXISTS "users_can_delete_referrals" ON public.referrals;

-- READ: Allowed if Admin, Creator, or Referring/Referred Org matches User's Org
CREATE POLICY "Unified Read Policy" ON public.referrals
FOR SELECT TO authenticated
USING (
  -- 1. Admins
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
  OR
  -- 2. Creator
  created_by = auth.uid()
  OR
  -- 3. Referred From (User's Org Name matches)
  (
    referred_from IS NOT NULL 
    AND 
    referred_from = (SELECT organization_name FROM public.users WHERE id = auth.uid())
  )
  OR
  -- 4. Referred To (User's Org Name matches)
  (
    referred_to IS NOT NULL 
    AND 
    referred_to = (SELECT organization_name FROM public.users WHERE id = auth.uid())
  )
);

-- INSERT: Authenticated users only
CREATE POLICY "Unified Insert Policy" ON public.referrals
FOR INSERT TO authenticated
WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: Admins or Creator or Target Org
CREATE POLICY "Unified Update Policy" ON public.referrals
FOR UPDATE TO authenticated
USING (
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
  OR
  created_by = auth.uid()
  OR
  (
    referred_to IS NOT NULL 
    AND 
    referred_to = (SELECT organization_name FROM public.users WHERE id = auth.uid())
  )
);

-- DELETE: Admins only
CREATE POLICY "Unified Delete Policy" ON public.referrals
FOR DELETE TO authenticated
USING (
  get_auth_role() IN ('admin', 'super_admin', 'state_admin')
);

DO $$
BEGIN
  RAISE NOTICE 'Security advisor issues resolved: search_path fixed, metadata usage replaced with table lookups.';
END $$;
