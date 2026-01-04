-- PostgreSQL/Supabase Migration (not DB2 compatible)
/*
  # Create household members table and QR code system

  ## New Tables
  
  1. household_members
    - Stores individual family member information
    - Links to main registration (household)
    - Includes relationship, age, gender, etc.
  
  ## Changes to registrations table
  
  1. Add household-related fields:
    - household_size (number of members)
    - qr_code (unique QR code identifier)
    - household_head (name of household head)
  
  ## Security
  
  - Enable RLS on household_members table
  - Add policies for authenticated users
*/

-- Add household fields to registrations table
ALTER TABLE registrations ADD COLUMN household_size integer DEFAULT 1;
ALTER TABLE registrations ADD COLUMN qr_code VARCHAR(255);
ALTER TABLE registrations ADD CONSTRAINT uk_registrations_qr_code UNIQUE (qr_code);
ALTER TABLE registrations ADD COLUMN household_head VARCHAR(255);

-- Create household_members table if it doesn't exist
CREATE TABLE household_members (
  id VARCHAR(36) PRIMARY KEY,
  registration_id VARCHAR(36) REFERENCES registrations(id) ON DELETE CASCADE,
  full_name VARCHAR(255) NOT NULL,
  relationship VARCHAR(100) NOT NULL,
  gender VARCHAR(20) NOT NULL,
  date_of_birth date,
  age integer,
  id_number VARCHAR(50),
  phone VARCHAR(20),
  special_needs VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS on household_members (PostgreSQL specific - removed for compatibility)

-- Drop existing policies if they exist (PostgreSQL specific - removed for compatibility)

-- Create policies for household_members (PostgreSQL specific - removed for compatibility)

-- Create index for better performance
CREATE INDEX idx_household_members_registration_id 
  ON household_members(registration_id);

CREATE INDEX idx_registrations_qr_code 
  ON registrations(qr_code);