-- =====================================================================
-- AptiQR — login-by-identifier helpers
--
-- Students sign in with Register Number, faculty with Faculty ID *or*
-- email, admin with email directly. Supabase Auth only signs in by
-- email+password, so every account's auth.users.email is a real or
-- synthetic address, and these two functions let the app resolve
-- "what email goes with this register number / faculty id" *before*
-- the user is authenticated — without exposing anything else about
-- the account. Both are safe to call anonymously (rate-limit at the
-- edge/App Check level in production).
-- =====================================================================

create or replace function public.lookup_student_login_email(p_register_number text)
returns text
language sql security definer stable set search_path = public as $$
  select p.email
  from public.students s
  join public.profiles p on p.id = s.id
  where s.register_number = p_register_number
    and p.is_active = true
  limit 1;
$$;

grant execute on function public.lookup_student_login_email(text) to anon, authenticated;

create or replace function public.lookup_faculty_login_email(p_identifier text)
returns text
language sql security definer stable set search_path = public as $$
  select p.email
  from public.faculty f
  join public.profiles p on p.id = f.id
  where (f.faculty_id = p_identifier or p.email = p_identifier)
    and p.is_active = true
  limit 1;
$$;

grant execute on function public.lookup_faculty_login_email(text) to anon, authenticated;
