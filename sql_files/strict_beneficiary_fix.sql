-- ============================================================================
-- STRICT BENEFICIARY FIX (ROLE CORRECTION)
-- Purpose: 
-- 1. Downgrade 'abdulfatahzainab48' to 'case_worker' so they don't see everything.
-- 2. Re-apply RLS to be explicitly clear about who sees what.
-- ============================================================================

-- 1. ROLE CORRECTION (Targeted Fix)
DO $$
BEGIN
  -- Update Public Profile
  UPDATE public.users 
  SET role = 'case_worker'
  WHERE email = 'abdulfatahzainab48@gmail.com';

  -- Update Auth Metadata (Crucial for RLS to work instantly)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    '"case_worker"'
  )
  WHERE email = 'abdulfatahzainab48@gmail.com';
  
  RAISE NOTICE 'Downgraded abdulfatahzainab48 to case_worker.';
END $$;


-- 2. REINFORCE RLS (Explicit Logic)
-- We ensure 'case_worker' is NOT included in the "View Org" logic accidentally.

ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- A. ADMINS (Global View)
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- B. ORGANIZATION ADMINS/MANAGERS (Org View)
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )

  OR

  -- C. CASE WORKERS / USERS (Strictly Own View)
  (
     -- Covers 'case_worker', 'viewer', or any other role not listed above
     created_by = auth.uid()
  )
);

RAISE NOTICE 'Strict RLS applied. Case Workers now restricted to own data.';
