-- ============================================================================
-- WDOS Migration 048 — Instant Volunteer Approval (Phase 52)
--
-- The reviewer is right: a silent 24-hour approval gap loses people. From
-- this migration, a volunteer registration is approved THE MOMENT it
-- arrives (controlled by the org setting auto_approve_volunteers, ON by
-- default — switch it off in SQL any time to return to manual review):
--   registration → approved application → welcome email with the
--   create-your-login link → #/claim → activation journey — one sitting.
-- The welcome email sends when the email layer is configured; the new
-- WDOS-hosted form (deployed with this phase) also shows the claim link
-- on screen immediately, so nobody depends on email alone.
-- ============================================================================

insert into public.org_settings (key, value)
values ('auto_approve_volunteers', 'true'::jsonb)
on conflict (key) do nothing;

create or replace function public.volunteer_auto_approve()
returns trigger
language plpgsql security definer set search_path = public as $$
declare enabled boolean; hq_unit uuid;
begin
  select coalesce((value #>> '{}')::boolean, false) into enabled
    from org_settings where key = 'auto_approve_volunteers';
  if not enabled then return new; end if;
  if new.status is distinct from 'submitted' then return new; end if;

  begin
    select id into hq_unit from org_units
     where level = 'headquarters' order by created_at limit 1;

    update volunteer_applications
       set status = 'approved',
           decision_reason = 'Auto-approved on registration (org policy)',
           decided_at = now()
     where id = new.id;

    if not exists (select 1 from applications
                    where lower(email) = lower(new.email)) then
      insert into applications (first_name, last_name, email, phone, network,
        org_unit_id, motivation, status, decision_reason, decided_at)
      values (
        coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
        coalesce(nullif(trim(substr(new.full_name,
          length(split_part(new.full_name, ' ', 1)) + 1)), ''), '-'),
        new.email, new.phone, coalesce(new.network, 'WGMN'), hq_unit,
        coalesce(new.payload ->> 'why', ''),
        'approved', 'Auto-approved volunteer registration', now());
    end if;

    -- welcome email (best-effort; sends when the email layer is on)
    perform send_email(new.email,
      coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
      'Welcome to WODDI — you are approved!',
      email_wrap('You are approved!',
        'Thank you for registering to serve with WODDI. Your application '
        || 'has been approved.' || e'\n\n'
        || 'Create your login now and begin your activation journey:'
        || e'\n' || 'https://woddiwdos.netlify.app/#/claim' || e'\n\n'
        || 'Use this same email address when creating your account. '
        || 'We are delighted to have you.'));
  exception when others then
    raise notice 'volunteer_auto_approve skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

drop trigger if exists volunteers_auto_approve on public.volunteer_applications;
create trigger volunteers_auto_approve
  after insert on public.volunteer_applications
  for each row execute function public.volunteer_auto_approve();

insert into public.schema_migrations (version, name)
values (48, 'instant_volunteer_approval') on conflict (version) do nothing;
