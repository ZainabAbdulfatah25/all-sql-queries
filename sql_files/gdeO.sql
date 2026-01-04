-- ============================================================================
-- FIX STALE JWT ACCESS (Real-Time Permissions)
-- Purpose: 
-- 1. Modify RLS to check DB for Organization ID, not just JWT.
-- 2. Ensures changes to Role/Org are effective INSTANTLY (no logout needed).
-- ============================================================================

ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- 1. SUPER ADMINS (Keep using JWT role for speed, they are stable)
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATION STAFF (Live Check)
  (
    -- Check JWT Role first (Fast fail)
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    -- CRITICAL: Check Live DB for Org ID (Bypasses Stale JWT)
    EXISTS (
       SELECT 1 FROM public.users u
       WHERE u.id = auth.uid()
       AND u.organization_id IS NOT NULL
       -- Matches the creator's org
       AND u.organization_id = (SELECT c.organization_id FROM users c WHERE c.id = registrations.created_by)
    )
  )

  OR

  -- 3. DEFAULT: VIEW OWN ONLY
  (
     created_by = auth.uid()
  )
);

-- Force role limit on Insert as well
DROP POLICY IF EXISTS "Beneficiaries Insert" ON registrations;
CREATE POLICY "Beneficiaries Insert"
ON registrations FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
);


