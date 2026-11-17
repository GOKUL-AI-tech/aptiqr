-- =====================================================================
-- AptiQR — Row Level Security policies
-- Run after schema.sql and auth_trigger.sql
--
-- Every `create policy` below is preceded by a matching `drop policy if
-- exists` — Postgres has no `create or replace policy`, so without this
-- re-running this file on a project that already ran it once (e.g. to
-- pick up the category-scoping changes below) fails with "policy already
-- exists" on the very first statement and none of the updated
-- definitions ever actually apply. Safe to run any number of times.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper functions (security definer so they can read profiles/students
-- without recursively triggering RLS on those tables)
-- ---------------------------------------------------------------------
create or replace function public.current_role_name()
returns user_role language sql security definer stable set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_faculty()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'faculty');
$$;

create or replace function public.current_faculty_department()
returns uuid language sql security definer stable set search_path = public as $$
  select department_id from public.faculty where id = auth.uid();
$$;

-- Which track (aptitude/technical/communication) the calling admin
-- manages — null for a non-admin caller. Used to scope question-bank
-- and daily-test read/write to that admin's own category (see the
-- "Restricted per category" admin model).
create or replace function public.current_admin_category()
returns test_category language sql security definer stable set search_path = public as $$
  select category from public.admins where id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------
alter table public.departments        enable row level security;
alter table public.profiles           enable row level security;
alter table public.students           enable row level security;
alter table public.faculty            enable row level security;
alter table public.admins             enable row level security;
alter table public.questions          enable row level security;
alter table public.daily_tests        enable row level security;
alter table public.daily_test_questions enable row level security;
alter table public.test_attempts      enable row level security;
alter table public.test_answers       enable row level security;
alter table public.rankings           enable row level security;

-- ---------------------------------------------------------------------
-- DEPARTMENTS — publicly readable (non-sensitive; the student login
-- screen shows a department picker before the user is authenticated),
-- only admin writes.
-- ---------------------------------------------------------------------
drop policy if exists "departments_select_all" on public.departments;
create policy "departments_select_all" on public.departments
  for select using (true);
drop policy if exists "departments_write_admin" on public.departments;
create policy "departments_write_admin" on public.departments
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- PROFILES — user sees/edits own row; admin sees/edits all;
-- faculty can read profiles of students in their department (join check
-- happens via the students policy, profiles read kept to self+admin to
-- keep this table minimal-exposure).
-- ---------------------------------------------------------------------
-- Was `id = auth.uid() or is_admin() or is_faculty()` — the comment above
-- always claimed department-scoping for faculty "happens via the
-- students policy", but nothing here actually enforced that: any
-- authenticated faculty account could read every profile row (email,
-- phone, photo_url — not just full_name) for every student, faculty, and
-- admin account in the college, not only their own department. The app
-- never exercises this today (faculty screens fetch student/ranking data
-- through the fetch_attendance/fetch_top_rankings SECURITY DEFINER RPCs,
-- which don't rely on this policy at all — see functions.sql), so
-- tightening it to actually match the students_select department scoping
-- doesn't remove anything the app currently uses.
drop policy if exists "profiles_select_self_or_admin" on public.profiles;
create policy "profiles_select_self_or_admin" on public.profiles
  for select using (
    id = auth.uid()
    or public.is_admin()
    or (public.is_faculty() and exists (
          select 1 from public.students s
          where s.id = profiles.id and s.department_id = public.current_faculty_department()
        ))
  );
drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid() or public.is_admin());
drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
  for insert with check (id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------
-- STUDENTS
-- ---------------------------------------------------------------------
drop policy if exists "students_select" on public.students;
create policy "students_select" on public.students
  for select using (
    id = auth.uid()
    or public.is_admin()
    or (public.is_faculty() and department_id = public.current_faculty_department())
  );
drop policy if exists "students_write_admin" on public.students;
create policy "students_write_admin" on public.students
  for insert with check (public.is_admin());
drop policy if exists "students_update_admin_or_self" on public.students;
create policy "students_update_admin_or_self" on public.students
  for update using (public.is_admin() or id = auth.uid());
drop policy if exists "students_delete_admin" on public.students;
create policy "students_delete_admin" on public.students
  for delete using (public.is_admin());

-- ---------------------------------------------------------------------
-- FACULTY
-- ---------------------------------------------------------------------
drop policy if exists "faculty_select" on public.faculty;
create policy "faculty_select" on public.faculty
  for select using (id = auth.uid() or public.is_admin());
drop policy if exists "faculty_write_admin" on public.faculty;
create policy "faculty_write_admin" on public.faculty
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- ADMINS
-- ---------------------------------------------------------------------
drop policy if exists "admins_select_self_or_admin" on public.admins;
create policy "admins_select_self_or_admin" on public.admins
  for select using (id = auth.uid() or public.is_admin());
-- Split from one blanket "any admin can write any admins row" policy
-- into insert (any admin — actual account creation goes through the
-- create-user edge function's service-role client anyway, which
-- bypasses RLS entirely, so this only covers a direct-client insert)
-- plus update/delete restricted to your OWN row. Previously an admin
-- could update or delete *any other* admin's row via a plain client
-- call — e.g. the Technical admin reassigning the Communication
-- admin's category, or deleting their account outright. Nothing in the
-- app's UI does this today, but nothing stopped it at the database
-- layer either.
drop policy if exists "admins_write_admin" on public.admins;
drop policy if exists "admins_insert_admin" on public.admins;
create policy "admins_insert_admin" on public.admins
  for insert with check (public.is_admin());
drop policy if exists "admins_update_self" on public.admins;
create policy "admins_update_self" on public.admins
  for update using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "admins_delete_self" on public.admins;
create policy "admins_delete_self" on public.admins
  for delete using (id = auth.uid());

-- ---------------------------------------------------------------------
-- QUESTIONS — each admin login only sees/manages their own category's
-- questions (Aptitude/Technical/Communication admins are fully siloed
-- from each other's banks); faculty read-only across all categories;
-- students never see the bank directly (they only get today's paper via
-- daily_test_questions).
-- ---------------------------------------------------------------------
drop policy if exists "questions_select_admin_faculty" on public.questions;
create policy "questions_select_admin_faculty" on public.questions
  for select using (
    (public.is_admin() and category = public.current_admin_category())
    or public.is_faculty()
  );
drop policy if exists "questions_write_admin" on public.questions;
create policy "questions_write_admin" on public.questions
  for all
  using (public.is_admin() and category = public.current_admin_category())
  with check (public.is_admin() and category = public.current_admin_category());

-- ---------------------------------------------------------------------
-- DAILY TESTS — everyone signed in can read every category (students/
-- faculty need to see all 3 of a day's tests); writes are also
-- restricted here for defense-in-depth, but the real enforcement for
-- generate/update/delete is inside those SECURITY DEFINER functions
-- (see functions.sql) since RPC calls bypass table-owner RLS anyway.
-- ---------------------------------------------------------------------
drop policy if exists "daily_tests_select_all" on public.daily_tests;
create policy "daily_tests_select_all" on public.daily_tests
  for select using (auth.uid() is not null);
drop policy if exists "daily_tests_write_admin" on public.daily_tests;
create policy "daily_tests_write_admin" on public.daily_tests
  for all
  using (public.is_admin() and category = public.current_admin_category())
  with check (public.is_admin() and category = public.current_admin_category());

-- ---------------------------------------------------------------------
-- DAILY TEST QUESTIONS — students only see the papers for tests they
-- have an in-progress/submitted attempt on (prevents peeking ahead);
-- admin/faculty see all.
-- ---------------------------------------------------------------------
drop policy if exists "dtq_select" on public.daily_test_questions;
create policy "dtq_select" on public.daily_test_questions
  for select using (
    public.is_admin() or public.is_faculty()
    or exists (
      select 1 from public.test_attempts a
      where a.daily_test_id = daily_test_questions.daily_test_id
        and a.student_id = auth.uid()
        and a.status in ('in_progress', 'submitted')
    )
  );
-- Category-scoped, matching questions_write_admin/daily_tests_write_admin
-- below — without the category check here, a direct PostgREST write
-- (bypassing generate_daily_test/update_daily_test, which DO check) let
-- an admin insert/delete question rows against another category's
-- daily_test_id, tampering with that category's live paper.
drop policy if exists "dtq_write_admin" on public.daily_test_questions;
create policy "dtq_write_admin" on public.daily_test_questions
  for all
  using (
    public.is_admin() and exists (
      select 1 from public.daily_tests dt
      where dt.id = daily_test_questions.daily_test_id and dt.category = public.current_admin_category()
    )
  )
  with check (
    public.is_admin() and exists (
      select 1 from public.daily_tests dt
      where dt.id = daily_test_questions.daily_test_id and dt.category = public.current_admin_category()
    )
  );

-- ---------------------------------------------------------------------
-- TEST ATTEMPTS
-- ---------------------------------------------------------------------
drop policy if exists "attempts_select" on public.test_attempts;
create policy "attempts_select" on public.test_attempts
  for select using (
    student_id = auth.uid()
    or public.is_admin()
    or (public.is_faculty() and exists (
          select 1 from public.students s
          where s.id = test_attempts.student_id
            and s.department_id = public.current_faculty_department()
        ))
  );
drop policy if exists "attempts_insert_self" on public.test_attempts;
create policy "attempts_insert_self" on public.test_attempts
  for insert with check (student_id = auth.uid() or public.is_admin());
drop policy if exists "attempts_update_self_or_admin" on public.test_attempts;
create policy "attempts_update_self_or_admin" on public.test_attempts
  for update using (student_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------
-- TEST ANSWERS — student can only touch answers on their own attempts
-- ---------------------------------------------------------------------
drop policy if exists "answers_select" on public.test_answers;
create policy "answers_select" on public.test_answers
  for select using (
    exists (select 1 from public.test_attempts a where a.id = test_answers.attempt_id and a.student_id = auth.uid())
    or public.is_admin()
    or (public.is_faculty() and exists (
          select 1 from public.test_attempts a
          join public.students s on s.id = a.student_id
          where a.id = test_answers.attempt_id
            and s.department_id = public.current_faculty_department()
        ))
  );
drop policy if exists "answers_write_self" on public.test_answers;
create policy "answers_write_self" on public.test_answers
  for all using (
    exists (select 1 from public.test_attempts a where a.id = test_answers.attempt_id and a.student_id = auth.uid())
    or public.is_admin()
  )
  with check (
    exists (select 1 from public.test_attempts a where a.id = test_answers.attempt_id and a.student_id = auth.uid())
    or public.is_admin()
  );

-- ---------------------------------------------------------------------
-- RANKINGS — published results readable by everyone signed in
-- (student sees own + department/year boards; faculty/admin see all)
-- ---------------------------------------------------------------------
drop policy if exists "rankings_select_all" on public.rankings;
create policy "rankings_select_all" on public.rankings
  for select using (auth.uid() is not null);
drop policy if exists "rankings_write_admin" on public.rankings;
create policy "rankings_write_admin" on public.rankings
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- Close the direct-write bypass on the scoring/test-generation tables.
--
-- attempts_update_self_or_admin (`using (student_id = auth.uid() or
-- is_admin())`) has no `with check` of its own, so Postgres defaults it
-- to the same as `using` — meaning a student could PATCH their *own*
-- test_attempts row via a plain PostgREST call and set `score`/`status`
-- to whatever they want, bypassing submit_test_attempt's server-computed
-- tally entirely. Likewise answers_write_self lets a student write
-- test_answers.is_correct directly instead of going through
-- submit_answer, which is the only thing that actually checks it against
-- questions.correct_option. And daily_tests_write_admin/dtq_write_admin
-- let an admin insert a daily_tests/daily_test_questions row directly,
-- recreating the "reports N questions, ships with fewer" bug that
-- generate_daily_test's pool-size guard exists specifically to prevent
-- (see functions.sql) — a raw insert skips that guard entirely.
--
-- The RLS policies above still do useful read-side and defense-in-depth
-- work, so they're left in place; this instead removes the underlying
-- table-level grants Supabase's `authenticated` role gets by default, so
-- there's no INSERT/UPDATE/DELETE left for RLS to even evaluate against
-- these four tables. The RPCs that legitimately need to write them
-- (start_test_attempt, submit_answer, submit_test_attempt,
-- cancel_test_attempt, publish_results, generate_daily_test,
-- update_daily_test, delete_daily_test) are all `security definer`, so
-- they run as the function owner and are unaffected by revoking the
-- calling role's own grants. Verified the Flutter app never writes these
-- four tables directly (only ever via .rpc(...) calls or plain .select()
-- reads) before applying this.
revoke insert, update, delete on public.test_attempts from authenticated;
revoke insert, update, delete on public.test_answers from authenticated;
revoke insert, update, delete on public.daily_tests from authenticated;
revoke insert, update, delete on public.daily_test_questions from authenticated;
