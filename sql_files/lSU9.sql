/*
  RESTORE360 User Details Fix
  
  This script fixes the issue where user details (Phone, Department) were not showing.
  
  Changes:
  1. Adds missing columns to `users` table: phone, department, organization_name, organization_type
  2. Updates `admin_create_user` function to correctly handle these fields
  3. Updates RLS policies to allow Admins to update any user
  
  INSTRUCTIONS:
  1. Go to Supabase Dashboard > SQL Editor
  2. Copy/Paste this entire script
  3. Run
*/

-- 1. Add missing columns to users table
DO $$
BEGIN
  -- Phone
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'phone') THEN
    ALTER TABLE users ADD COLUMN phone text;
  END IF;

  -- Department
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'department') THEN
    ALTER TABLE users ADD COLUMN department text;
  END IF;

  -- Organization Name (if missing)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'organization_name') THEN
    ALTER TABLE users ADD COLUMN organization_name text;
  END IF;

  -- Organization Type (if missing)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'organization_type') THEN
    ALTER TABLE users ADD COLUMN organization_type text;
  END IF;
END $$;


-- 2. Update admin_create_user function to include new fields
CREATE OR REPLACE FUNCTION admin_create_user(
  p_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_organization_name TEXT DEFAULT NULL,
  p_organization_type TEXT DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_role TEXT;
  v_new_user users;
BEGIN
  -- Get current user's role
  SELECT role INTO v_current_user_role
  FROM users
  WHERE id = auth.uid();

  -- Check permissions (Admin or Organization creating non-admin)
  IF v_current_user_role = 'admin' OR (v_current_user_role = 'organization' AND p_role != 'admin') THEN
    
    INSERT INTO users (
      id, 
      email, 
      name, 
      role, 
      phone, 
      department, 
      organization_name, 
      organization_type
    )
    VALUES (
      p_id, 
      p_email, 
      p_name, 
      p_role, 
      p_phone, 
      p_department, 
      p_organization_name, 
      p_organization_type
    )
    ON CONFLICT (id) DO UPDATE
    SET
      email = EXCLUDED.email,
      name = EXCLUDED.name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone,
      department = EXCLUDED.department,
      organization_name = EXCLUDED.organization_name,
      organization_type = EXCLUDED.organization_type,
      updated_at = now()
    RETURNING * INTO v_new_user;
    
    RETURN v_new_user;
  ELSE
    RAISE EXCEPTION 'Unauthorized: Insufficient permissions to create user with role %', p_role;
  END IF;
END;
$$;


-- 3. Fix RLS Policies to allow Admins to update users
-- First, drop the existing restricted update policy if it exists
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Admins can update all users" ON users;

-- Re-create "Users can update own profile"
CREATE POLICY "Users can update own profile"
  ON users FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Create "Admins can update all users"
CREATE POLICY "Admins can update all users"
  ON users FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Verify policies
COMMENT ON TABLE users IS 'User profiles with fixed RLS policies';
