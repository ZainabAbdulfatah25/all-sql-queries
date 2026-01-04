/*
  # Fix Authentication and Profile Creation

  ## Changes
  1. Add trigger to automatically create user profile when auth user is created
  2. Add service role policy to allow automatic profile creation
  3. Ensure RLS is compatible
*/

-- 1. Enable RLS on user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies
DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Allow profile creation on signup" ON public.user_profiles;

-- 3. Create permissive insert policy for system-level inserts
CREATE POLICY "Allow profile creation on signup"
  ON public.user_profiles
  FOR INSERT
  TO public
  WITH CHECK (true);

-- 4. Create function to handle new user profile creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (
    id,
    email,
    first_name,
    last_name,
    profile_image
  )
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

-- 5. Create trigger to run function after new auth user is inserted
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
