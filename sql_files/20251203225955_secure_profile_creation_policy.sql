/*
  # Secure Profile Creation Policy

  ## Changes
  1. Replace overly permissive profile creation policy
  2. Users can only insert their own profile (matching auth.uid())
  3. Trigger function uses SECURITY DEFINER to bypass RLS

  ## Security
  - Restrictive RLS: Users can only create profiles for their own auth ID
  - Database trigger bypasses RLS using SECURITY DEFINER
  - Maintains secure access control
*/

-- Drop the overly permissive policy
DROP POLICY IF EXISTS "Allow profile creation on signup" ON user_profiles;

-- Create secure policy that only allows users to insert their own profile
CREATE POLICY "Users can insert own profile"
  ON user_profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);
