æ
-- Update User Roles Constraint
-- This script updates the check constraint on the users table to allow the new roles.

-- 1. Drop the existing check constraint (if it exists)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_role_check'
    ) THEN
        ALTER TABLE public.users DROP CONSTRAINT users_role_check;
    END IF;
END $$;

-- 2. Add the updated check constraint with ALL new roles
ALTER TABLE public.users
ADD CONSTRAINT users_role_check
CHECK (role IN (
    'admin', 
    'state_admin', 
    'organization', 
    'manager', 
    'case_worker', 
    'field_worker', 
    'field_officer', 
    'ordinary_user', 
    'viewer',
    -- New Roles
    'hr',
    'operations',
    'finance',
    'it_support',
    'monitoring_evaluation',
    'communications',
    'logistics',
    'legal',
    'program_coordinator',
    'counselor',
    'data_entry',
    'education',
    'intern',
    'nutrition',
    'protection',
    'shelter',
    'volunteer',
    'wash'
));

-- 3. (Optional) If you have a separate roles table or enum type, update that instead.
--    Assuming 'user_role' enum type exists:
-- ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'hr';
-- ... (repeat for all roles)

-- 4. Log the update
DO $$
BEGIN
    RAISE NOTICE 'Successfully updated users table role constraint to include all staff roles.';
END $$;
æ
"(35be1d26e08ff29d37d06411bdf542658bbc5af82Bfile:///home/zainab/Restore360/restore360_update_roles_sectors.sql:file:///home/zainab/Restore360