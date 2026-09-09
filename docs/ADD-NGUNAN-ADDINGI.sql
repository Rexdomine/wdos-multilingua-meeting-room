-- Hon. Ngunan Addingi — Country Representative, Nigeria (WGMN)
-- Puts her into the leader directory so she appears on HQ → Accounts with a
-- "Create login" button already filled in. Safe to run twice.
insert into public.leader_directory (member_code, first_name, last_name, email, country, role_applied, sent_at)
values ('CR-NGA', 'Ngunan', 'Addingi', 'beekasinvest@gmail.com', 'Nigeria', 'Country Representative', now())
on conflict (member_code) do update
  set first_name = excluded.first_name, last_name = excluded.last_name,
      email = excluded.email, country = excluded.country, role_applied = excluded.role_applied;

-- Confirm:
select member_code, first_name, last_name, email, country, role_applied, claimed_profile
from public.leader_directory where member_code = 'CR-NGA';
