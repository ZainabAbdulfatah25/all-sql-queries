/*
  # Optimize RLS policies for registrations table

  ## Changes
  
  Update policies with optimized auth function calls
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Users can update registrations" ON registrations;
DROP POLICY IF EXISTS "Users can delete registrations" ON registrations;

-- Create optimized policies
CREATE POLICY "Users can update registrations"
  ON registrations FOR UPDATE
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

CREATE POLICY "Users can delete registrations"
  ON registrations FOR DELETE
  TO authenticated
  USING (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role = 'admin'
    ))
  );
