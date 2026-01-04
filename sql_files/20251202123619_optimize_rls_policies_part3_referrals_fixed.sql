/*
  # Optimize RLS policies for referrals table

  ## Changes
  
  Recreate policies with optimized auth function calls
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view referrals" ON referrals;
DROP POLICY IF EXISTS "Users can create referrals" ON referrals;
DROP POLICY IF EXISTS "Users can update referrals" ON referrals;
DROP POLICY IF EXISTS "Users can delete referrals" ON referrals;

-- Create optimized policies
CREATE POLICY "Users can view referrals"
  ON referrals FOR SELECT
  TO authenticated
  USING (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role IN ('admin', 'organization')
    ))
  );

CREATE POLICY "Users can create referrals"
  ON referrals FOR INSERT
  TO authenticated
  WITH CHECK (created_by = (select auth.uid()));

CREATE POLICY "Users can update referrals"
  ON referrals FOR UPDATE
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

CREATE POLICY "Users can delete referrals"
  ON referrals FOR DELETE
  TO authenticated
  USING (
    (created_by = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role = 'admin'
    ))
  );
