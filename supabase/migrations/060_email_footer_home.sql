-- ============================================================================
-- WDOS Migration 060 — Every email signs off from the real home (Phase 72.1)
-- The branded wrapper's footer now reads "The Nurturer · woddicrm.org"
-- (fixing both the old netlify address and the raw \u00b7 escape that was
-- printing literally). Every outgoing email inherits this immediately.
-- ============================================================================
create or replace function public.email_wrap(title text, body text)
returns text language sql immutable as $$
  select '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;'
      || 'margin:0 auto;border:1px solid #eee;border-radius:10px;overflow:hidden">'
      || '<div style="background:#D4006A;color:#fff;padding:18px 22px;'
      || 'font-size:20px;font-weight:800">WODDI</div>'
      || '<div style="padding:22px"><h2 style="margin:0 0 10px;color:#111">'
      || title || '</h2><p style="color:#333;line-height:1.6;white-space:pre-line">'
      || body || '</p><p style="color:#7CB518;font-weight:700;margin-top:18px">'
      || 'The Nurturer &middot; <a href="https://woddicrm.org" '
      || 'style="color:#7CB518;text-decoration:none">woddicrm.org</a>'
      || '</p></div></div>'
$$;

insert into public.schema_migrations (version, name)
values (60, 'email_footer_home') on conflict (version) do nothing;
