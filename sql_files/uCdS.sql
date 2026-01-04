-- Enable pg_net extension to make HTTP requests from the database
create extension if not exists pg_net;

-- Function to call the Edge Function
create or replace function public.trigger_email_notification()
returns trigger
language plpgsql
security definer
as $$
declare
  payload jsonb;
  recipient_email text;
  recipient_name text;
  
  -- Preferences
  user_email_enabled boolean;
  user_case_updates boolean;
  user_referral_updates boolean;
  
  -- Vars for Referrals
  dest_org_id uuid;
  param_sender_org_name text;
  
  edge_function_url text := 'https://weifuvktryxfvqiwdzsy.supabase.co/functions/v1/send-email';
  service_role_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndlaWZ1dmt0cnl4ZnZxaXdkenN5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTM2NDYwNCwiZXhwIjoyMDgwOTQwNjA0fQ.bImHYuLh5rQ1RB4U_IrDMFOFVre8Pa_VBfWYhHZEmzo';
  
  target_user_id uuid;
begin

  -- ============================================================
  -- 1. WELCOME EMAIL (Users/Insert)
  -- ============================================================
  if TG_TABLE_NAME = 'users' and TG_OP = 'INSERT' then
    if coalesce(new.notification_email_enabled, true) is true then
      recipient_email := new.email;
      recipient_name := new.name;
      payload := jsonb_build_object(
        'type', 'welcome_email',
        'recipient_email', recipient_email,
        'recipient_name', recipient_name,
        'data', jsonb_build_object('role', new.role)
      );
      
      -- Send immediately for this single case
      perform net.http_post(
        url := edge_function_url,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_role_key),
        body := payload
      );
    end if;
    return new; -- Exit early
  end if;


  -- ============================================================
  -- 2. CASE UPDATES (Cases/Update)
  -- ============================================================
  if TG_TABLE_NAME = 'cases' and TG_OP = 'UPDATE' then
    target_user_id := coalesce(new.assigned_to, new.created_by);
    
    if target_user_id is not null then
      select email, name, notification_email_enabled, notification_case_updates 
      into recipient_email, recipient_name, user_email_enabled, user_case_updates 
      from public.users where id = target_user_id;

      -- Check Global & Case Preferences
      if recipient_email is not null 
         and coalesce(user_email_enabled, true) is true 
         and coalesce(user_case_updates, true) is true then
        
        -- Build Payload based on Sub-Event
        if new.assigned_to is not null and (old.assigned_to is null or new.assigned_to != old.assigned_to) then
           payload := jsonb_build_object('type', 'case_assignment', 'recipient_email', recipient_email, 'recipient_name', recipient_name, 'data', jsonb_build_object('case_id', new.id, 'case_number', new.case_number, 'title', new.title, 'priority', new.priority));
        
        elsif new.approval_status = 'approved' and (old.approval_status != 'approved' or old.approval_status is null) then
           payload := jsonb_build_object('type', 'case_approved', 'recipient_email', recipient_email, 'recipient_name', recipient_name, 'data', jsonb_build_object('case_id', new.id, 'case_number', new.case_number, 'title', new.title));
        
        elsif new.approval_status = 'rejected' and (old.approval_status != 'rejected' or old.approval_status is null) then
           payload := jsonb_build_object('type', 'case_declined', 'recipient_email', recipient_email, 'recipient_name', recipient_name, 'data', jsonb_build_object('case_id', new.id, 'case_number', new.case_number, 'title', new.title, 'rejection_reason', coalesce(new.rejection_reason, 'No reason provided')));
        
        elsif new.status = 'closed' and (old.status != 'closed') then
           payload := jsonb_build_object('type', 'case_closed', 'recipient_email', recipient_email, 'recipient_name', recipient_name, 'data', jsonb_build_object('case_id', new.id, 'case_number', new.case_number, 'title', new.title));
        end if;

        -- Send if payload exists
        if payload is not null then
          perform net.http_post(
            url := edge_function_url,
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_role_key),
            body := payload
          );
        end if;
      end if;
    end if;
    return new; -- Exit early
  end if;


  -- ============================================================
  -- 3. REFERRAL NOTIFICATIONS (Referrals/Insert)
  -- ============================================================
  if TG_TABLE_NAME = 'referrals' and TG_OP = 'INSERT' then
    -- Attempt to identify Destination Organization ID
    -- Support both 'assigned_organization_id' (uuid) setup or 'referred_to' if it stores an ID
    if new.assigned_organization_id is not null then
       dest_org_id := new.assigned_organization_id;
    else
       -- Fallback: If 'referred_to' is a UUID, try to cast it. If not, text lookup might be needed but skipping for safety/simplicity
       begin
         dest_org_id := new.referred_to::uuid;
       exception when others then
         dest_org_id := null;
       end;
    end if;

    if dest_org_id is not null then
      -- Loop through ELIGIBLE users of that Organization (Admins/Org Role) who have notifications enabled
      for recipient_email, recipient_name in 
        select email, name from public.users 
        where organization_id = dest_org_id 
        and (role in ('organization', 'admin', 'state_admin', 'manager')) -- Adjust roles as needed
        and coalesce(notification_email_enabled, true) is true
        and coalesce(notification_referral_updates, true) is true
      loop
        
        -- Get Sender Name (either from referred_from text or ID lookup)
        param_sender_org_name := new.referred_from; -- Default to raw text
        
        -- Build Payload
        payload := jsonb_build_object(
          'type', 'referral_notification',
          'recipient_email', recipient_email,
          'recipient_name', recipient_name,
          'data', jsonb_build_object(
            'referral_id', new.id,
            'sender_org', param_sender_org_name,
            'reason', new.reason
          )
        );

        -- Send Email
        perform net.http_post(
          url := edge_function_url,
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_role_key),
          body := payload
        );
        
      end loop;
    end if;
    return new;
  end if;

  return new;
end;
$$;

-- Create Triggers

-- 1. Users
drop trigger if exists on_new_user_email on public.users;
create trigger on_new_user_email
  after insert on public.users
  for each row execute procedure public.trigger_email_notification();

-- 2. Cases
drop trigger if exists on_case_status_email on public.cases;
create trigger on_case_status_email
  after update on public.cases
  for each row execute procedure public.trigger_email_notification();

-- 3. Referrals (NEW)
drop trigger if exists on_referral_arrival_email on public.referrals;
create trigger on_referral_arrival_email
  after insert on public.referrals
  for each row execute procedure public.trigger_email_notification();
