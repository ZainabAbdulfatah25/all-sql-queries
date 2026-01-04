-- ============================================================================
-- RESTORE360 EMERGENCY FIX (MASTER SCRIPT)
-- Purpose:
-- 1. FIX PERMISSIONS: Force-promotes 'zainab.abdulfatah' to Admin (handling any email TLD).
-- 2. FIX USER CREATION: Updates logic to prevent "Permission Denied" errors.
-- 3. FIX ACTIVITY LOGS: Populates missing "Recent Activity" history.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. FORCE ADMIN PROMOTION (Broad Match)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_count INT;
BEGIN
  -- Update Public Profile (The one the app checks)
  UPDATE public.users 
  SET role = 'admin'
  WHERE email ILIKE 'zainab.abdulfatah%';

  -- Update Auth Metadata (The fallback)
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    '"admin"'
  )
  WHERE email ILIKE 'zainab.abdulfatah%';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Promoted % users matching "zainab.abdulfatah" pattern to Admin.', v_count;
END $$;


-- ----------------------------------------------------------------------------
-- 2. UPDATE USER CREATION LOGIC (Robust Logic)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_create_user(
  p_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_organization_name TEXT DEFAULT NULL,
  p_organization_type TEXT DEFAULT NULL,
  p_organization_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID;
  v_creator_role TEXT;
  v_creator_org_id UUID;
  v_creator_org_name TEXT;
  v_final_org_id UUID;
BEGIN
  v_uid := auth.uid();

  -- A. ROBUST ROLE FETCHING (Prioritize Public Table, then Metadata)
  SELECT role INTO v_creator_role FROM public.users WHERE id = v_uid;

  IF v_creator_role IS NULL THEN
    SELECT COALESCE(raw_user_meta_data->>'role', 'viewer')
    INTO v_creator_role
    FROM auth.users 
    WHERE id = v_uid;
  END IF;

  v_creator_role := COALESCE(v_creator_role, 'organization');

  -- B. ORGANIZATION FETCHING
  SELECT organization_id, organization_name 
  INTO v_creator_org_id, v_creator_org_name 
  FROM public.users WHERE id = v_uid;

  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') THEN
    v_final_org_id := p_organization_id;
  ELSE
    v_final_org_id := v_creator_org_id; 
  END IF;

  -- C. PERMISSION CHECK
  IF v_creator_role IN ('admin', 'super_admin', 'state_admin') OR 
     (v_creator_role IN ('organization', 'manager') AND p_role NOT IN ('admin', 'super_admin', 'state_admin')) THEN
    
    INSERT INTO public.users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
    VALUES (p_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, COALESCE(p_organization_name, v_creator_org_name), p_organization_type, p_description)
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone,
      department = EXCLUDED.department,
      organization_id = EXCLUDED.organization_id,
      description = EXCLUDED.description,
      updated_at = now();

    -- Auto-Fix Login
    UPDATE auth.users SET email_confirmed_at = now() WHERE id = p_id;
    
    RETURN (SELECT u FROM public.users u WHERE id = p_id);

  ELSE
    RAISE EXCEPTION 'Permission Denied: You (%) cannot create a %.', v_creator_role, p_role;
  END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 3. POPULATE ACTIVITY LOGS
-- ----------------------------------------------------------------------------
-- A. From Registrations
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 'create', 'beneficiaries', 'Registered beneficiary: ' || full_name, created_at, id::text
FROM registrations
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = registrations.created_by)
AND NOT EXISTS (SELECT 1 FROM activity_logs WHERE resource_id = registrations.id::text AND action = 'create');

-- B. From Cases
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 'create', 'cases', 'Opened case: ' || title, created_at, id::text
FROM cases
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = cases.created_by)
AND NOT EXISTS (SELECT 1 FROM activity_logs WHERE resource_id = cases.id::text AND action = 'create');

-- C. From Referrals
INSERT INTO activity_logs (user_id, action, module, description, created_at, resource_id)
SELECT DISTINCT
  created_by, 'create', 'referrals', 'Sent referral for: ' || COALESCE(client_name, 'Client'), created_at, id::text
FROM referrals
WHERE created_by IS NOT NULL
AND EXISTS (SELECT 1 FROM public.users WHERE id = referrals.created_by)
AND NOT EXISTS (SELECT 1 FROM activity_logs WHERE resource_id = referrals.id::text AND action = 'create');


COMMIT;
