-- Fix User Visibility RLS
-- Ensure Organization Admins can view users in their own organization.

-- 1. Check if the policy exists, if not create/replace it.
-- Current issue: 'get_all_users' RPC might be bypassing RLS but filtering incorrectly, or RLS on 'public.users' prevents select.

DROP POLICY IF EXISTS "Organization admins can view their own organization users" ON public.users;

CREATE POLICY "Organization admins can view their own organization users"
ON public.users
FOR SELECT
TO authenticated
USING (
  -- Admin/State Admin can see all
  (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'state_admin')
  OR
  -- Users can see themselves
  auth.uid() = id
  OR
  -- Organization Admins/Managers can see users in their org
  (
    (SELECT role FROM public.users WHERE id = auth.uid()) IN ('organization', 'manager')
    AND
    organization_id = (SELECT organization_id FROM public.users WHERE id = auth.uid())
  )
);

-- Also update 'get_all_users' RPC function if it exists to respect these rules more explicitly or just rely on RLS if it does 'SELECT * FROM users'.
-- Assuming 'get_all_users' does a simple select, RLS should apply.

-- Grant access just in case
GRANT SELECT ON public.users TO authenticated;
