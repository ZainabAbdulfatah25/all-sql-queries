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
  edge_function_url text := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-email'; -- REPLACE THIS
  service_role_key text := 'YOUR_SERVICE_ROLE_KEY'; -- REPLACE THIS (or use vault)
  target_user_id uuid;
begin
  -- Logic to determine recipient and payload based on table and event
  
  -- CASE: New User (Welcome Email)
  -- Note: This usually runs after INSERT on public.users
  if TG_TABLE_NAME = 'users' and TG_OP = 'INSERT' then
    recipient_email := new.email;
    recipient_name := new.name;
    payload := jsonb_build_object(
      'type', 'welcome_email',
      'recipient_email', recipient_email,
      'recipient_name', recipient_name,
      'data', jsonb_build_object('role', new.role)
    );
  end if;

  -- CASE UPDATES (Assignments, Status Changes)
  if TG_TABLE_NAME = 'cases' and TG_OP = 'UPDATE' then
    -- Determine Recipient: Default to Assigned User, fallback to Creator if unassigned
    target_user_id := coalesce(new.assigned_to, new.created_by);
    
    if target_user_id is not null then
      select email, name into recipient_email, recipient_name from public.users where id = target_user_id;
    end if;

    if recipient_email is not null then
      
      -- 1. New Assignment
      if new.assigned_to is not null and (old.assigned_to is null or new.assigned_to != old.assigned_to) then
         payload := jsonb_build_object(
          'type', 'case_assignment',
          'recipient_email', recipient_email,
          'recipient_name', recipient_name,
          'data', jsonb_build_object(
            'case_id', new.id,
            'case_number', new.case_number,
            'title', new.title,
            'priority', new.priority
          )
        );
      end if;

      -- 2. Case Approved
      if new.approval_status = 'approved' and (old.approval_status != 'approved' or old.approval_status is null) then
         payload := jsonb_build_object(
          'type', 'case_approved',
          'recipient_email', recipient_email,
          'recipient_name', recipient_name,
          'data', jsonb_build_object(
            'case_id', new.id,
            'case_number', new.case_number,
            'title', new.title
          )
        );
      end if;

      -- 3. Case Declined (Rejected)
      if new.approval_status = 'rejected' and (old.approval_status != 'rejected' or old.approval_status is null) then
         payload := jsonb_build_object(
          'type', 'case_declined',
          'recipient_email', recipient_email,
          'recipient_name', recipient_name,
          'data', jsonb_build_object(
            'case_id', new.id,
            'case_number', new.case_number,
            'title', new.title,
            'rejection_reason', coalesce(new.rejection_reason, 'No reason provided')
          )
        );
      end if;

      -- 4. Case Closed
      if new.status = 'closed' and (old.status != 'closed') then
         payload := jsonb_build_object(
          'type', 'case_closed',
          'recipient_email', recipient_email,
          'recipient_name', recipient_name,
          'data', jsonb_build_object(
            'case_id', new.id,
            'case_number', new.case_number,
            'title', new.title
          )
        );
      end if;

    end if;
  end if;

  -- If we successfully built a payload, send the request
  if payload is not null then
    perform net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := payload
    );
  end if;

  return new;
end;
$$;

-- Create Triggers
drop trigger if exists on_new_user_email on public.users;
create trigger on_new_user_email
  after insert on public.users
  for each row execute procedure public.trigger_email_notification();

drop trigger if exists on_case_status_email on public.cases;
create trigger on_case_status_email
  after update on public.cases
  for each row execute procedure public.trigger_email_notification();

-- Note: You need to replace YOUR_PROJECT_REF and YOUR_SERVICE_ROLE_KEY in the function.
