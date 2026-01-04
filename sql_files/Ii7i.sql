-- ============================================================================
-- FIX INDIVIDUAL ISOLATION & SYNTAX
-- Purpose: 
-- 1. Unlink 'abdulfatahzainab48' from Defensera (they are an individual).
-- 2. Downgrade Role to 'case_worker'.
-- 3. Re-apply Strict RLS (Syntax Error Free).
-- ============================================================================

-- 1. UNLINK FROM ORGANIZATION (Data Fix)
DO $$
BEGIN
  -- Remove Org Link
  UPDATE public.users 
  SET organization_id = NULL, organization_name = NULL, role = 'case_worker'
  WHERE email = 'abdulfatahzainab48@gmail.com';

  -- Update Auth Metadata (Reflect the Change)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_build_object(
    'role', 'case_worker',
    'organization_id', NULL
  )
  WHERE email = 'abdulfatahzainab48@gmail.com';
END $$;


-- 2. REINFORCE RLS (STRICT & SYNTAX ERROR FREE)
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- A. ADMINS (Global View)
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- B. ORGANIZATION ADMINS (View All in Org - IF they have an org)
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    get_auth_user_org_id() IS NOT NULL
    AND
    EXISTS (
      SELECT 1 FROM users creator 
      WHERE creator.id = registrations.created_by 
      AND creator.organization_id = get_auth_user_org_id()
    )
  )

  OR

  -- C. INDIVIDUALS / CASE WORKERS (Strictly Own View)
  (
     created_by = auth.uid()
  )
);
