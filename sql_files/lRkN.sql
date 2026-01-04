-- ============================================================================
-- FIX INDIVIDUAL ORGANIZATION DISPLAY
-- Purpose: 
-- 1. Unlink 'individual' users from 'Defensera' if they were wrongly adopted.
-- 2. Ensure users like 'gololomusa@gmail.com' have NULL organization.
-- 3. Disable any "Auto-Adoption" triggers that force users into Defensera.
-- ============================================================================

DO $$
BEGIN
  -- 1. Fix Specific User (gololomusa@gmail.com)
  UPDATE users
  SET organization_id = NULL, organization_name = NULL
  WHERE email = 'gololomusa@gmail.com';

  -- 2. Fix All 'Individual' Users wrongly assigned to Defensera
  --    (Assuming user_type 'individual' implies they shouldn't be in an Org)
  UPDATE users
  SET organization_id = NULL, organization_name = NULL
  WHERE user_type = 'individual' AND organization_name = 'Defensera';

  RAISE NOTICE 'Fixed Individual Users organization display.';
END $$;

-- 3. DROP ORPHAN ADOPTION TRIGGERS (If they exist)
--    This prevents future users from being auto-assigned.
DROP TRIGGER IF EXISTS trigger_adopt_orphan_user ON public.users;
DROP FUNCTION IF EXISTS public.adopt_orphan_user();

-- Also check for auth table triggers
DROP TRIGGER IF EXISTS on_auth_user_created_adoption ON auth.users;
