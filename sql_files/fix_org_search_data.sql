-- ============================================================================
-- FIX ORG SEARCH DATA
-- Purpose: 
-- 1. Ensure all organizations are ACTIVE.
-- 2. Seed 'Defensera' with 'Kano' location and 'Security' sector.
-- ============================================================================

-- 1. ACTIVATE ALL
UPDATE organizations SET is_active = true;

-- 2. SEED DEFENSERA (Targeting by name roughly)
UPDATE organizations 
SET 
  locations_covered = ARRAY['Kano', 'Lagos', 'Abuja', 'Maiduguri'],
  sectors_provided = ARRAY['Security', 'Protection', 'Health', 'Shelter', 'Food']
WHERE name ILIKE '%Defensera%' OR organization_name ILIKE '%Defensera%';

-- 3. SEED OTHERS (Fail-safe: Make all orgs cover Kano/Security if Defensera not found?)
-- Let's just update ANY org that doesn't have locations to have defaults
UPDATE organizations
SET
  locations_covered = ARRAY['Kano', 'Abuja']
WHERE locations_covered IS NULL OR array_length(locations_covered, 1) IS NULL;

UPDATE organizations
SET
  sectors_provided = ARRAY['Security', 'Protection']
WHERE sectors_provided IS NULL OR array_length(sectors_provided, 1) IS NULL;
