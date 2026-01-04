-- ============================================================================
-- FIX USER CREATION SESSION DROP (SERVER-SIDE CREATION)
-- Purpose: 
-- 1. Create 'auth.users' record INSIDE the RPC function.
-- 2. Avoid using 'supabase.auth.signUp()' on client which kills session.
-- ============================================================================

-- Need pgdigest extension for password hashing if we want to set passwords manualy
-- However, raw insertion into auth.users requires handling encrypted passwords.
-- EASIER APPROACH: Use Supabase's 'auth.uid()' and 'auth.email()' are not settable safely without knowing encryption.
-- BETTER: Use a trigger? No, too complex.
-- STANDARD: Use `extensions.uuid_generate_v4()`

-- We will allow 'admin_create_user' to INSERT into auth.users.
-- NOTE: We cannot easily hash the password to bcrypt format in pure PL/PGSQL without pgcrypto.
-- checking if pgcrypto is available... usually yes in Supabase.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION admin_create_user(
  p_email TEXT,
  p_password TEXT,
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
  v_new_id UUID;
  v_creator_role TEXT;
  v_creator_org_id UUID;
  v_creator_org_name TEXT;
  v_final_org_id UUID;
  v_final_org_name TEXT;
  v_encrypted_pw TEXT;
BEGIN
  v_uid := auth.uid();

  -- 1. GET CREATOR CONTEXT
  SELECT role, organization_id, organization_name 
  INTO v_creator_role, v_creator_org_id, v_creator_org_name 
  FROM public.users WHERE id = v_uid;

  IF v_creator_role IS NULL THEN v_creator_role := 'viewer'; END IF;

  -- 2. DETERMINE ORGANIZATION
  v_final_org_id := p_organization_id;
  v_final_org_name := p_organization_name;

  IF (v_final_org_id IS NULL) OR (v_creator_role NOT IN ('admin', 'super_admin', 'state_admin')) THEN
     v_final_org_id := v_creator_org_id;
     v_final_org_name := v_creator_org_name;
  END IF;

  -- 3. CREATE AUTH USER (Raw Insert)
  -- This bypasses client-side session switching
  v_new_id := gen_random_uuid();
  v_encrypted_pw := crypt(p_password, gen_salt('bf')); -- BCrypt hash

  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_new_id,
    'authenticated',
    'authenticated',
    p_email,
    v_encrypted_pw,
    now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    jsonb_build_object('name', p_name, 'role', p_role, 'organization_id', v_final_org_id, 'organization_name', v_final_org_name),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );
  
  -- Insert into identities for completeness (Supabase sometimes checks this)
  INSERT INTO auth.identities (
     id,
     user_id, 
     identity_data, 
     provider, 
     last_sign_in_at, 
     created_at, 
     updated_at
  ) VALUES (
     v_new_id,
     v_new_id,
     jsonb_build_object('sub', v_new_id, 'email', p_email),
     'email',
     now(),
     now(),
     now()
  );


  -- 4. CREATE PUBLIC USER (Standard Insert)
  -- Note: The trigger might fire, but ON CONFLICT handles it.
  INSERT INTO public.users (id, email, name, role, phone, department, organization_id, organization_name, organization_type, description)
  VALUES (v_new_id, p_email, p_name, p_role, p_phone, p_department, v_final_org_id, v_final_org_name, p_organization_type, p_description)
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    phone = EXCLUDED.phone,
    department = EXCLUDED.department,
    organization_id = EXCLUDED.organization_id,
    organization_name = EXCLUDED.organization_name,
    description = EXCLUDED.description,
    updated_at = now();

  RETURN (SELECT u FROM public.users u WHERE id = v_new_id);
END;
$$;
