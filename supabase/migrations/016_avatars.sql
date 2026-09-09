-- ============================================================================
-- WDOS Migration 016 — Staff/Profile Avatars
-- Public-read storage bucket (faces shown here are already on WODDI's public
-- website); writing is restricted to the person themself or HQ. Objects are
-- named by profile id, no extension.
-- Write authority is a single explicitly-granted helper so it evaluates
-- identically in the storage API's request context.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create or replace function public.can_write_avatar(obj_name text)
returns boolean
language sql stable security definer set search_path = public as $$
  select obj_name = auth.uid()::text
      or exists (
        select 1 from role_assignments
        where profile_id = auth.uid()
          and ends_at is null
          and role in ('super_admin','executive_director','hq_team')
      );
$$;

grant execute on function public.can_write_avatar(text) to authenticated;

drop policy if exists avatars_insert on storage.objects;
drop policy if exists avatars_update on storage.objects;
drop policy if exists avatars_delete on storage.objects;

create policy avatars_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and public.can_write_avatar(name));

create policy avatars_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and public.can_write_avatar(name))
  with check (bucket_id = 'avatars' and public.can_write_avatar(name));

create policy avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and public.can_write_avatar(name));

insert into public.schema_migrations (version, name)
values (16, 'avatars') on conflict (version) do nothing;
