-- =====================================================================
-- AptiQR — auth.users -> public.profiles bootstrap
-- On signup, app passes role/full_name/etc in auth user's raw_user_meta_data.
-- This trigger creates the matching profiles row automatically.
-- Role-specific rows (students/faculty/admins) are inserted by the app
-- right after signup, inside the same onboarding transaction (see
-- lib/services/auth_service.dart), because they need extra fields
-- (register_number, department, faculty_id, etc.) that aren't part of
-- Supabase Auth metadata by default.
-- =====================================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, full_name, email, phone)
  values (
    new.id,
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'student'),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
