-- ============================================================================
-- WDOS Migration 100 — instant approval at BOTH doors (Phase 118)
--
-- People registering through the main "Apply to join WODDI" form were
-- landing in a manual review queue and then hitting the claim page's
-- honest-but-blocking "it is with the review team" message. Org policy
-- (per Azeez, 28 Aug): applications are accepted the moment they are
-- submitted, on both doors, matching the volunteer form's behaviour
-- since migration 048.
--
-- How: application_intake (051) previously sent a "with our team for
-- review" email. It now approves the row instead. The existing
-- applications_decided_mail trigger (051) then fires on that status
-- change and sends the "you are approved, create your login" email —
-- so each new applicant gets exactly ONE email, the right one.
-- The claim door and signup handler already honour approved
-- applications (072/098), so approval is the only missing piece.
--
-- Backfill: everyone currently parked as submitted, under_review or
-- recommended is approved now; the decided-mail trigger emails each of
-- them their claim invitation as the update lands. Stuck volunteer
-- registrations (rare auto-approve failures) are released the same way.
-- Rejected and withdrawn applications are NOT touched.
-- ============================================================================

-- ---- new arrivals: approve on intake ------------------------------------
create or replace function public.application_intake()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.status = 'submitted' then
      update applications
         set status = 'approved',
             decided_at = now(),
             decision_reason =
               'Provisionally approved on registration (org policy)'
       where id = new.id;
      -- applications_decided_mail fires on that update and sends the
      -- approval email with the claim link; no separate intake email.
    end if;
  exception when others then
    raise notice 'application_intake skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

-- ---- the backlog: release everyone waiting ------------------------------
update public.applications
   set status = 'approved',
       decided_at = now(),
       decision_reason =
         'Provisionally approved on registration (org policy)'
 where status in ('submitted', 'under_review', 'recommended');

update public.volunteer_applications
   set status = 'approved',
       decided_at = now(),
       decision_reason =
         'Provisionally approved on registration (org policy)'
 where status = 'submitted';

insert into public.schema_migrations (version, name)
values (100, 'instant_approval_all_doors') on conflict (version) do nothing;
