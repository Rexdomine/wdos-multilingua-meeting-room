-- ============================================================================
-- WDOS Migration 051 — The Apply Form Speaks (Phase 58)
-- (File companion for the SQL applied live on 2026-07-26; recorded here so
--  the migrations folder matches the ledger. Safe to re-run: idempotent.)
-- ============================================================================
insert into public.org_settings (key, value)
values ('auto_approve_members', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.application_intake()
returns trigger
language plpgsql security definer set search_path = public as $$
declare auto_on boolean;
begin
  if new.status is distinct from 'submitted' then return new; end if;
  begin
    select coalesce((value #>> '{}')::boolean, false) into auto_on
      from org_settings where key = 'auto_approve_members';
    if auto_on then
      update applications
         set status = 'approved',
             decision_reason = 'Auto-approved on application (org policy)',
             decided_at = now()
       where id = new.id;
    else
      perform send_email(new.email,
        coalesce(nullif(new.first_name, ''), 'Friend'),
        'WODDI received your application',
        email_wrap('Application received',
          'Thank you for applying to join WODDI, '
          || coalesce(nullif(new.first_name, ''), 'friend') || '!'
          || e'\n\nYour application is now with our team for review. '
          || 'You will receive an email the moment a decision is made.'
          || e'\n\nWith warmth,\nThe WODDI Team'));
    end if;
  exception when others then
    raise notice 'application_intake skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

drop trigger if exists applications_intake on public.applications;
create trigger applications_intake
  after insert on public.applications
  for each row execute function public.application_intake();

create or replace function public.application_decided_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    begin
      perform send_email(new.email,
        coalesce(nullif(new.first_name, ''), 'Friend'),
        'Welcome to WODDI — you are approved!',
        email_wrap('You are approved!',
          'Wonderful news, '
          || coalesce(nullif(new.first_name, ''), 'friend')
          || ' — your WODDI application has been approved.'
          || e'\n\nCreate your login now and begin your activation journey:'
          || e'\nhttps://woddicrm.org/#/claim'
          || e'\n\nUse this same email address when creating your account.'));
    exception when others then
      raise notice 'application_decided_mail skipped for %: %', new.email, sqlerrm;
    end;
  end if;
  return new;
end; $$;

drop trigger if exists applications_decided_mail on public.applications;
create trigger applications_decided_mail
  after update of status on public.applications
  for each row execute function public.application_decided_mail();

insert into public.schema_migrations (version, name)
values (51, 'apply_form_speaks') on conflict (version) do nothing;
