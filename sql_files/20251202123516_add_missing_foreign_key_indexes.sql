/*
  # Add missing foreign key indexes

  ## Performance Improvements
  
  1. Add indexes for foreign keys to improve query performance:
     - cases.approved_by
     - organizations.created_by
     - referrals.approved_by
     - registrations.approved_by
  
  These indexes significantly improve JOIN and WHERE clause performance
  when querying by these foreign key columns.
*/

-- Add index for cases.approved_by
CREATE INDEX IF NOT EXISTS idx_cases_approved_by 
  ON cases(approved_by);

-- Add index for organizations.created_by
CREATE INDEX IF NOT EXISTS idx_organizations_created_by 
  ON organizations(created_by);

-- Add index for referrals.approved_by
CREATE INDEX IF NOT EXISTS idx_referrals_approved_by 
  ON referrals(approved_by);

-- Add index for registrations.approved_by
CREATE INDEX IF NOT EXISTS idx_registrations_approved_by 
  ON registrations(approved_by);
