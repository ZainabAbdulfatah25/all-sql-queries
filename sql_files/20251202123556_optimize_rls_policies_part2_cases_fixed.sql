/*
  # Optimize RLS policies for cases table

  ## Changes
  
  1. Drop existing policies
  2. Recreate with optimized auth function calls using (select auth.uid())
*/

-- Drop all existing policies
DROP POLICY IF EXISTS "Users can view cases" ON cases;
DROP POLICY IF EXISTS "Users can create cases" ON cases;
DROP POLICY IF EXISTS "Users can update cases" ON cases;
DROP POLICY IF EXISTS "Users can delete cases" ON cases;

-- Create optimized policies
CREATE POLICY "Users can view cases"
  ON cases FOR SELECT
  TO authenticated
  USING (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role IN ('admin', 'organization')
    ))
  );

CREATE POLICY "Users can create cases"
  ON cases FOR INSERT
  TO authenticated
  WITH CHECK (created_by = (select auth.uid()));

CREATE POLICY "Users can update cases"
  ON cases FOR UPDATE
  TO authenticated
  USING (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role IN ('admin', 'organization')
    ))
  )
  WITH CHECK (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role IN ('admin', 'organization')
    ))
  );

CREATE POLICY "Users can delete cases"
  ON cases FOR DELETE
  TO authenticated
  USING (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role = 'admin'
    ))
  );
