-- Fix RLS policies for Referrals table V2 (Nuclear Option)
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

-- Dynamic Cleanup: Drop ALL policies on referrals table to ensure no conflicts
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'referrals' AND schemaname = 'public' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.referrals', pol.policyname);
  END LOOP;
END $$;

-- 1. INSERT Policy: Allow any authenticated user to create a referral
CREATE POLICY "authenticated_can_create_referrals" 
ON referrals FOR INSERT 
TO authenticated 
WITH CHECK (true);

-- 2. SELECT Policy: 
-- Users can see referrals they created
-- Organizations can see referrals assigned to them
-- Admins (state_admin) can see all referrals
CREATE POLICY "users_can_view_referrals" 
ON referrals FOR SELECT 
TO authenticated 
USING (
    created_by = auth.uid() OR 
    assigned_organization_id IN (
        SELECT id FROM organizations WHERE id = assigned_organization_id
    ) OR
    (auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' IN ('admin', 'state_admin') OR
    assigned_organization_id = (SELECT organization_id FROM users WHERE id = auth.uid())
);

-- 3. UPDATE Policy:
CREATE POLICY "users_can_update_referrals" 
ON referrals FOR UPDATE 
TO authenticated 
USING (
    created_by = auth.uid() OR
    assigned_organization_id = (SELECT organization_id FROM users WHERE id = auth.uid()) OR
    (auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' IN ('admin', 'state_admin')
);

-- 4. DELETE Policy:
CREATE POLICY "users_can_delete_referrals" 
ON referrals FOR DELETE 
TO authenticated 
USING (
    created_by = auth.uid() OR
    (auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' IN ('admin', 'state_admin')
);

-- Grant permissions to authenticated users
GRANT ALL ON referrals TO authenticated;
