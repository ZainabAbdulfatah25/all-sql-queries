-- ============================================================================
-- ENABLE ASSIGNMENT
-- Purpose: 
-- 1. Add 'assigned_organization_id' to registrations.
-- 2. Update RLS so assigned organizations can SEE and EDIT the record.
-- ============================================================================

-- A. SCHEMA CHANGE
-- Add the column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'registrations' AND column_name = 'assigned_organization_id') THEN
    ALTER TABLE registrations ADD COLUMN assigned_organization_id UUID REFERENCES organizations(id);
  END IF;
END $$;


-- B. UPDATE RLS (Visibility)
ALTER TABLE registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Beneficiaries Visibility" ON registrations;

CREATE POLICY "Beneficiaries Visibility"
ON registrations FOR SELECT TO authenticated
USING (
  -- 1. ADMINS
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin')
  
  OR
  
  -- 2. ORGANIZATION STAFF (Creator OR Assigned)
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    get_auth_user_org_id() IS NOT NULL
    AND
    (
       -- Originally Created by this Org
       EXISTS (
         SELECT 1 FROM public.users u
         WHERE u.id = registrations.created_by
         AND u.organization_id = get_auth_user_org_id()
       )
       OR
       -- Explicitly Assigned to this Org
       registrations.assigned_organization_id = get_auth_user_org_id()
    )
  )

  OR

  -- 3. INDIVIDUALS / CREATOR
  (
     created_by = auth.uid()
  )
);


-- C. UPDATE RLS (Edit Rights)
DROP POLICY IF EXISTS "Beneficiaries Update" ON registrations;
CREATE POLICY "Beneficiaries Update"
ON registrations FOR UPDATE TO authenticated
USING (
  get_auth_user_role() IN ('admin', 'state_admin', 'super_admin') OR
  created_by = auth.uid() OR
  (
    get_auth_user_role() IN ('organization', 'manager') 
    AND 
    get_auth_user_org_id() IS NOT NULL 
    AND 
    (
      -- Created by same org
      EXISTS (SELECT 1 FROM public.users u WHERE u.id = registrations.created_by AND u.organization_id = get_auth_user_org_id())
      OR
      -- Assigned to this org
      registrations.assigned_organization_id = get_auth_user_org_id()
    )
  )
);
