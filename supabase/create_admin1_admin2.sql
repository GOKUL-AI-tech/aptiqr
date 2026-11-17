-- =====================================================================
-- AptiQR — creates the Technical and Communication admin logins.
--
-- Prerequisites:
--   1. schema.sql / policies.sql / functions.sql already re-run with the
--      category changes (public.admins.category must exist).
--   2. Both auth users already created via Dashboard → Authentication →
--      Users → Add user, with "Auto Confirm User" checked:
--        admin1@example.com / <choose a strong password>
--        admin2@example.com / <choose a strong password>
--
-- Looks the users up by email rather than requiring you to paste UUIDs
-- manually. Safe to re-run (upserts).
-- =====================================================================

do $$
declare
  v_admin1_id uuid;
  v_admin2_id uuid;
begin
  select id into v_admin1_id from auth.users where email = 'admin1@example.com';
  select id into v_admin2_id from auth.users where email = 'admin2@example.com';

  if v_admin1_id is null then
    raise exception 'admin1@example.com not found in auth.users — create it first via Authentication > Users > Add user';
  end if;
  if v_admin2_id is null then
    raise exception 'admin2@example.com not found in auth.users — create it first via Authentication > Users > Add user';
  end if;

  -- handle_new_user only sets profiles.role from the user's metadata at
  -- signup time — the Dashboard's "Add user" form doesn't set that
  -- metadata, so without this these two would default to role='student'
  -- and never reach the admin console at all.
  insert into public.profiles (id, role, full_name, email)
  values (v_admin1_id, 'admin', 'Technical Admin', 'admin1@example.com')
  on conflict (id) do update set role = 'admin', full_name = excluded.full_name, email = excluded.email;

  insert into public.profiles (id, role, full_name, email)
  values (v_admin2_id, 'admin', 'Communication Admin', 'admin2@example.com')
  on conflict (id) do update set role = 'admin', full_name = excluded.full_name, email = excluded.email;

  -- admin1 -> Technical, admin2 -> Communication (per your answer above).
  insert into public.admins (id, category) values (v_admin1_id, 'technical')
  on conflict (id) do update set category = 'technical';

  insert into public.admins (id, category) values (v_admin2_id, 'communication')
  on conflict (id) do update set category = 'communication';

  raise notice 'admin1@example.com -> Technical admin, admin2@example.com -> Communication admin. Done.';
end $$;
