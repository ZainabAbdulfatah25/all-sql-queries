/*
  # Fix Household Members RLS Policies

  This script adds comprehensive RLS policies for the `household_members` table
  to ensure authenticated users can manage family members correctly.
*/

-- Enable RLS just in case
ALTER TABLE household_members ENABLE ROW LEVEL SECURITY;

-- 1. Grant access to authenticated users
GRANT ALL ON household_members TO authenticated;

-- 2. Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can view household members" ON household_members;
DROP POLICY IF EXISTS "Users can insert household members" ON household_members;
DROP POLICY IF EXISTS "Users can update household members" ON household_members;
DROP POLICY IF EXISTS "Users can delete household members" ON household_members;

-- 3. Create new comprehensive policies

-- Policy: INSERT
-- Allow authenticated users to add members
CREATE POLICY "Users can insert household members"
ON household_members
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Policy: SELECT
-- Allow authenticated users to view members
CREATE POLICY "Users can view household members"
ON household_members
FOR SELECT
TO authenticated
USING (true);

-- Policy: UPDATE
-- Allow authenticated users to update members
CREATE POLICY "Users can update household members"
ON household_members
FOR UPDATE
TO authenticated
USING (true);

-- Policy: DELETE
-- Allow authenticated users to delete members
CREATE POLICY "Users can delete household members"
ON household_members
FOR DELETE
TO authenticated
USING (true);

-- Verify policies
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM
    pg_policies
WHERE
    tablename = 'household_members';
