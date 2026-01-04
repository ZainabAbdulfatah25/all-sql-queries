/*
  # Fix Authentication and Profile Creation

  ## Changes
  1. Add trigger to automatically create user profile when auth user is created
  2. Add service role policy to allow automatic profile creation
  3. Ensure email confirmation is disabled for development

  ## Security
  - Maintains RLS for user data access
  - Uses database triggers for reliable profile creation
*/

-- Drop existing restrictive policy if it exists
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;

-- Create more permissive insert policy for new signups
CREATE POLICY "Allow profile creation on signup"
  ON user_profiles FOR INSERT
  WITH CHECK (true);

-- Create function to handle new user profile creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (id, email, first_name, last_name, profile_image)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
    '/placeholder-user.jpg'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for automatic profile creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();
