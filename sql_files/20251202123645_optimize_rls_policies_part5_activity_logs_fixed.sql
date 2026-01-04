/*
  # Optimize RLS policies for activity_logs table

  ## Changes
  
  Update policies with optimized auth function calls
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view activity logs" ON activity_logs;
DROP POLICY IF EXISTS "Users can create activity logs" ON activity_logs;

-- Create optimized policies
CREATE POLICY "Users can view activity logs"
  ON activity_logs FOR SELECT
  TO authenticated
  USING (
    (user_id = (select auth.uid())) OR 
    (EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = (select auth.uid())
      AND users.role = 'admin'
    ))
  );

CREATE POLICY "Users can create activity logs"
  ON activity_logs FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (select auth.uid()));
