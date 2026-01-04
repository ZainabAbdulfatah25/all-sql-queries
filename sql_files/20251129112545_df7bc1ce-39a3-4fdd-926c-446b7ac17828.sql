-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create enum for user roles (hierarchical)
CREATE TYPE public.app_role AS ENUM ('super_admin', 'partner_admin', 'case_manager', 'field_officer', 'viewer');

-- Create enum for displacement causes
CREATE TYPE public.displacement_cause AS ENUM ('conflict', 'natural_disaster', 'development_induced', 'other');

-- Create enum for service types
CREATE TYPE public.service_type AS ENUM ('shelter', 'food', 'healthcare', 'education', 'psychosocial', 'livelihood', 'protection', 'wash', 'nfi', 'other');

-- Create enum for referral status
CREATE TYPE public.referral_status AS ENUM ('pending', 'accepted', 'in_progress', 'completed', 'rejected');

-- Create enum for case status
CREATE TYPE public.case_status AS ENUM ('open', 'in_progress', 'under_review', 'closed');

-- Create enum for solution intentions
CREATE TYPE public.solution_intention AS ENUM ('return', 'local_integration', 'relocation', 'undecided');

-- Create enum for vulnerability levels
CREATE TYPE public.vulnerability_level AS ENUM ('critical', 'high', 'medium', 'low');

-- Organizations table
CREATE TABLE public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- User roles table
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role app_role NOT NULL,
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, role)
);

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Households table
CREATE TABLE public.households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_code TEXT UNIQUE NOT NULL,
  qr_code TEXT,
  head_of_household_name TEXT NOT NULL,
  registration_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
  current_lga TEXT NOT NULL,
  current_state TEXT NOT NULL,
  gps_coordinates TEXT,
  household_size INTEGER DEFAULT 1,
  registered_by UUID REFERENCES auth.users(id),
  organization_id UUID REFERENCES public.organizations(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- IDPs/Returnees table
CREATE TABLE public.idps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE NOT NULL,
  nin TEXT,
  restore_id TEXT UNIQUE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  middle_name TEXT,
  date_of_birth DATE,
  age INTEGER,
  gender TEXT NOT NULL,
  phone TEXT,
  photo_url TEXT,
  is_head_of_household BOOLEAN DEFAULT false,
  relationship_to_head TEXT,
  marital_status TEXT,
  education_level TEXT,
  occupation TEXT,
  skills TEXT[],
  has_disability BOOLEAN DEFAULT false,
  disability_type TEXT,
  chronic_illness BOOLEAN DEFAULT false,
  illness_details TEXT,
  registered_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Displacement history table
CREATE TABLE public.displacement_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idp_id UUID REFERENCES public.idps(id) ON DELETE CASCADE NOT NULL,
  origin_lga TEXT NOT NULL,
  origin_state TEXT NOT NULL,
  origin_community TEXT,
  displacement_cause displacement_cause NOT NULL,
  cause_details TEXT,
  displacement_date DATE NOT NULL,
  perpetrating_actors TEXT,
  times_displaced INTEGER DEFAULT 1,
  previous_locations TEXT[],
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Service referrals table
CREATE TABLE public.service_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  idp_id UUID REFERENCES public.idps(id) ON DELETE CASCADE,
  service_type service_type NOT NULL,
  service_description TEXT,
  urgency TEXT,
  referring_organization_id UUID REFERENCES public.organizations(id),
  receiving_organization_id UUID REFERENCES public.organizations(id),
  status referral_status DEFAULT 'pending',
  rejection_reason TEXT,
  initiated_by UUID REFERENCES auth.users(id),
  accepted_by UUID REFERENCES auth.users(id),
  completed_by UUID REFERENCES auth.users(id),
  initiated_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
  accepted_date TIMESTAMP WITH TIME ZONE,
  completed_date TIMESTAMP WITH TIME ZONE,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Cases table
CREATE TABLE public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_number TEXT UNIQUE NOT NULL,
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  idp_id UUID REFERENCES public.idps(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  status case_status DEFAULT 'open',
  priority TEXT,
  assigned_to UUID REFERENCES auth.users(id),
  created_by UUID REFERENCES auth.users(id),
  closed_by UUID REFERENCES auth.users(id),
  closure_notes TEXT,
  opened_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
  closed_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Case notes table
CREATE TABLE public.case_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE NOT NULL,
  note TEXT NOT NULL,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Durable solutions assessments table
CREATE TABLE public.durable_solutions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE NOT NULL,
  assessment_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
  solution_intention solution_intention,
  safety_security_score INTEGER CHECK (safety_security_score >= 0 AND safety_security_score <= 10),
  housing_score INTEGER CHECK (housing_score >= 0 AND housing_score <= 10),
  standard_of_living_score INTEGER CHECK (standard_of_living_score >= 0 AND standard_of_living_score <= 10),
  livelihood_score INTEGER CHECK (livelihood_score >= 0 AND livelihood_score <= 10),
  documentation_score INTEGER CHECK (documentation_score >= 0 AND documentation_score <= 10),
  family_reunification_score INTEGER CHECK (family_reunification_score >= 0 AND family_reunification_score <= 10),
  social_cohesion_score INTEGER CHECK (social_cohesion_score >= 0 AND social_cohesion_score <= 10),
  essential_services_score INTEGER CHECK (essential_services_score >= 0 AND essential_services_score <= 10),
  overall_score NUMERIC GENERATED ALWAYS AS (
    (COALESCE(safety_security_score, 0) + COALESCE(housing_score, 0) + COALESCE(standard_of_living_score, 0) + 
     COALESCE(livelihood_score, 0) + COALESCE(documentation_score, 0) + COALESCE(family_reunification_score, 0) + 
     COALESCE(social_cohesion_score, 0) + COALESCE(essential_services_score, 0)) / 8.0
  ) STORED,
  notes TEXT,
  assessed_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Vulnerability assessments table
CREATE TABLE public.vulnerability_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE NOT NULL,
  assessment_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
  vulnerability_level vulnerability_level,
  risk_score NUMERIC,
  female_headed BOOLEAN DEFAULT false,
  unaccompanied_minors BOOLEAN DEFAULT false,
  elderly_members BOOLEAN DEFAULT false,
  pregnant_lactating BOOLEAN DEFAULT false,
  disability_present BOOLEAN DEFAULT false,
  chronic_illness_present BOOLEAN DEFAULT false,
  single_parent BOOLEAN DEFAULT false,
  child_headed BOOLEAN DEFAULT false,
  gbv_survivor BOOLEAN DEFAULT false,
  protection_concerns TEXT[],
  economic_vulnerability BOOLEAN DEFAULT false,
  documentation_gaps BOOLEAN DEFAULT false,
  displacement_duration_months INTEGER,
  times_displaced INTEGER,
  urgent_needs TEXT[],
  recommendations TEXT,
  assessed_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Service history table
CREATE TABLE public.service_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  idp_id UUID REFERENCES public.idps(id) ON DELETE CASCADE,
  service_type service_type NOT NULL,
  service_description TEXT,
  provider_organization_id UUID REFERENCES public.organizations(id),
  service_date TIMESTAMP WITH TIME ZONE DEFAULT now(),
  recorded_by UUID REFERENCES auth.users(id),
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Documents table
CREATE TABLE public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  idp_id UUID REFERENCES public.idps(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL,
  document_name TEXT NOT NULL,
  file_url TEXT NOT NULL,
  file_size INTEGER,
  mime_type TEXT,
  is_verified BOOLEAN DEFAULT false,
  verified_by UUID REFERENCES auth.users(id),
  expiry_date DATE,
  uploaded_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Follow-ups table
CREATE TABLE public.follow_ups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID REFERENCES public.households(id) ON DELETE CASCADE NOT NULL,
  follow_up_type TEXT NOT NULL,
  scheduled_date DATE NOT NULL,
  completed_date DATE,
  assigned_to UUID REFERENCES auth.users(id),
  status TEXT DEFAULT 'pending',
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX idx_user_roles_role ON public.user_roles(role);
CREATE INDEX idx_profiles_organization_id ON public.profiles(organization_id);
CREATE INDEX idx_households_organization_id ON public.households(organization_id);
CREATE INDEX idx_households_current_lga ON public.households(current_lga);
CREATE INDEX idx_idps_household_id ON public.idps(household_id);
CREATE INDEX idx_idps_nin ON public.idps(nin);
CREATE INDEX idx_displacement_history_idp_id ON public.displacement_history(idp_id);
CREATE INDEX idx_service_referrals_household_id ON public.service_referrals(household_id);
CREATE INDEX idx_service_referrals_status ON public.service_referrals(status);
CREATE INDEX idx_cases_household_id ON public.cases(household_id);
CREATE INDEX idx_cases_status ON public.cases(status);
CREATE INDEX idx_cases_assigned_to ON public.cases(assigned_to);
CREATE INDEX idx_durable_solutions_household_id ON public.durable_solutions(household_id);
CREATE INDEX idx_vulnerability_assessments_household_id ON public.vulnerability_assessments(household_id);

-- Enable Row Level Security
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.displacement_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.case_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.durable_solutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vulnerability_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follow_ups ENABLE ROW LEVEL SECURITY;

-- Create security definer function to check user roles
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- Create security definer function to get user's organization
CREATE OR REPLACE FUNCTION public.get_user_organization(_user_id UUID)
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT organization_id
  FROM public.profiles
  WHERE id = _user_id
  LIMIT 1
$$;

-- RLS Policies for organizations (all authenticated users can view)
CREATE POLICY "Authenticated users can view organizations"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Super admins can manage organizations"
  ON public.organizations FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'));

-- RLS Policies for user_roles (super admins only)
CREATE POLICY "Super admins can manage user roles"
  ON public.user_roles FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Users can view their own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- RLS Policies for profiles
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Super admins can view all profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'));

-- RLS Policies for households (organization-based access)
CREATE POLICY "Users can view households in their organization"
  ON public.households FOR SELECT
  TO authenticated
  USING (
    organization_id = public.get_user_organization(auth.uid()) OR
    public.has_role(auth.uid(), 'super_admin')
  );

CREATE POLICY "Field officers and above can create households"
  ON public.households FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_role(auth.uid(), 'field_officer') OR
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

CREATE POLICY "Field officers and above can update households"
  ON public.households FOR UPDATE
  TO authenticated
  USING (
    (organization_id = public.get_user_organization(auth.uid()) AND
     (public.has_role(auth.uid(), 'field_officer') OR
      public.has_role(auth.uid(), 'case_manager') OR
      public.has_role(auth.uid(), 'partner_admin'))) OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for IDPs (inherit from households)
CREATE POLICY "Users can view IDPs in their organization"
  ON public.idps FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = idps.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Field officers and above can manage IDPs"
  ON public.idps FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = idps.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    ) AND (
      public.has_role(auth.uid(), 'field_officer') OR
      public.has_role(auth.uid(), 'case_manager') OR
      public.has_role(auth.uid(), 'partner_admin') OR
      public.has_role(auth.uid(), 'super_admin')
    )
  );

-- RLS Policies for displacement_history
CREATE POLICY "Users can view displacement history in their organization"
  ON public.displacement_history FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.idps i
      JOIN public.households h ON h.id = i.household_id
      WHERE i.id = displacement_history.idp_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Field officers and above can manage displacement history"
  ON public.displacement_history FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'field_officer') OR
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for service_referrals
CREATE POLICY "Users can view referrals in their organization"
  ON public.service_referrals FOR SELECT
  TO authenticated
  USING (
    referring_organization_id = public.get_user_organization(auth.uid()) OR
    receiving_organization_id = public.get_user_organization(auth.uid()) OR
    public.has_role(auth.uid(), 'super_admin')
  );

CREATE POLICY "Field officers and above can create referrals"
  ON public.service_referrals FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_role(auth.uid(), 'field_officer') OR
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

CREATE POLICY "Case managers and above can update referrals"
  ON public.service_referrals FOR UPDATE
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for cases
CREATE POLICY "Users can view cases in their organization"
  ON public.cases FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = cases.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    ) OR assigned_to = auth.uid()
  );

CREATE POLICY "Case managers and above can manage cases"
  ON public.cases FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for case_notes
CREATE POLICY "Users can view case notes for accessible cases"
  ON public.case_notes FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.cases c
      JOIN public.households h ON h.id = c.household_id
      WHERE c.id = case_notes.case_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             c.assigned_to = auth.uid() OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Case managers and above can add case notes"
  ON public.case_notes FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for durable_solutions
CREATE POLICY "Users can view durable solutions in their organization"
  ON public.durable_solutions FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = durable_solutions.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Case managers and above can manage durable solutions"
  ON public.durable_solutions FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for vulnerability_assessments
CREATE POLICY "Users can view vulnerability assessments in their organization"
  ON public.vulnerability_assessments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = vulnerability_assessments.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Case managers and above can manage vulnerability assessments"
  ON public.vulnerability_assessments FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for service_history
CREATE POLICY "Users can view service history in their organization"
  ON public.service_history FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = service_history.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Field officers and above can add service history"
  ON public.service_history FOR INSERT
  TO authenticated
  WITH CHECK (
    public.has_role(auth.uid(), 'field_officer') OR
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for documents
CREATE POLICY "Users can view documents in their organization"
  ON public.documents FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = documents.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    )
  );

CREATE POLICY "Field officers and above can manage documents"
  ON public.documents FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'field_officer') OR
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- RLS Policies for follow_ups
CREATE POLICY "Users can view follow-ups in their organization"
  ON public.follow_ups FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.households h
      WHERE h.id = follow_ups.household_id
        AND (h.organization_id = public.get_user_organization(auth.uid()) OR
             public.has_role(auth.uid(), 'super_admin'))
    ) OR assigned_to = auth.uid()
  );

CREATE POLICY "Case managers and above can manage follow-ups"
  ON public.follow_ups FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'case_manager') OR
    public.has_role(auth.uid(), 'partner_admin') OR
    public.has_role(auth.uid(), 'super_admin')
  );

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_households_updated_at BEFORE UPDATE ON public.households
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_idps_updated_at BEFORE UPDATE ON public.idps
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_service_referrals_updated_at BEFORE UPDATE ON public.service_referrals
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_cases_updated_at BEFORE UPDATE ON public.cases
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_follow_ups_updated_at BEFORE UPDATE ON public.follow_ups
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Create function to auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
    NEW.email
  );
  RETURN NEW;
END;
$$;

-- Trigger to create profile on signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();