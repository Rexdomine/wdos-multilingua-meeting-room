-- ============================================================================
-- WDOS Migration 003 — handle_new_user must tolerate missing name metadata
-- Users created via the Supabase dashboard carry no first/last name, which
-- violated profiles' name length checks and aborted user creation entirely.
-- Fallbacks: first_name <- email local part (title-cased), last_name <- '-'.
-- The recruitment pipeline (Phase 2) always captures real names; these
-- fallbacks only apply to manually created accounts.
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, first_name, last_name, email, network)
  values (
    new.id,
    left(coalesce(
      nullif(new.raw_user_meta_data->>'first_name', ''),
      initcap(split_part(new.email, '@', 1))
    ), 60),
    left(coalesce(
      nullif(new.raw_user_meta_data->>'last_name', ''),
      '-'
    ), 60),
    new.email,
    coalesce((new.raw_user_meta_data->>'network')::public.network_code, 'WGMN')
  );
  return new;
end; $$;
