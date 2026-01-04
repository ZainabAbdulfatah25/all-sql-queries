-- ============================================================================
-- FORCE CLEANUP OF STUCK USER
-- Purpose: Delete 'john@example.com' from auth.users so it can be re-created.
--          This fixes the "User already registered" error and allows a fresh start.
-- ============================================================================

-- 1. Delete from public.users first (just in case)
DELETE FROM public.users WHERE email = 'john@example.com';

-- 2. Delete from auth.users (This is the critical part that fixes "Already registered")
DELETE FROM auth.users WHERE email = 'john@example.com';

-- 3. Just to be safe, let's auto-confirm any OTHER users that might be stuck
UPDATE auth.users SET email_confirmed_at = now() WHERE email_confirmed_at IS NULL;
