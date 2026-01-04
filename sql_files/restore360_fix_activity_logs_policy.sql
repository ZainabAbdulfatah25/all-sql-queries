-- Enable RLS on activity_logs
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

-- Allow users to insert their own logs
CREATE POLICY "Users can insert their own logs" ON activity_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow admins (and others if needed) to view all logs
-- For simplicity, if we want detailed user activity reports for admins:
CREATE POLICY "Admins can view all logs" ON activity_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE users.id = auth.uid() 
      AND users.role IN ('admin', 'state_admin', 'manager', 'operations') -- Adjust roles as needed
    )
  );

-- Allow users to view their own logs
CREATE POLICY "Users can view their own logs" ON activity_logs
  FOR SELECT USING (auth.uid() = user_id);
