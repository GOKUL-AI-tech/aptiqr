-- =====================================================================
-- AptiQR — Daily Aptitude Test
-- Nehru Arts & Science College, Coimbatore
-- Supabase schema: tables, indexes, triggers
-- Run this file first, then policies.sql, then functions.sql (optional).
-- =====================================================================

create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------
do $$ begin
  create type user_role as enum ('student', 'faculty', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type attempt_status as enum ('not_started', 'in_progress', 'submitted', 'absent');
exception when duplicate_object then null; end $$;

do $$ begin
  create type test_status as enum ('draft', 'scheduled', 'open', 'closed', 'published');
exception when duplicate_object then null; end $$;

do $$ begin
  create type selection_mode as enum ('auto', 'manual');
exception when duplicate_object then null; end $$;

do $$ begin
  create type question_difficulty as enum ('easy', 'medium', 'hard');
exception when duplicate_object then null; end $$;

-- Broad subject-area partition — separate from `questions.subject` /
-- `questions.topic` (which stay free-text sub-topics, e.g. "Quantitative
-- Aptitude" or "C Programming"). This is the dimension the 3 admin
-- logins (one per category) and the 3 parallel daily tests/QRs are
-- partitioned by.
do $$ begin
  create type test_category as enum ('aptitude', 'technical', 'communication');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- DEPARTMENTS  (AIML, CSE, IT, ECE, BCA, MCA ...)
-- ---------------------------------------------------------------------
create table if not exists public.departments (
  id            uuid primary key default uuid_generate_v4(),
  code          text not null unique,          -- e.g. 'CSE'
  name          text not null,                 -- e.g. 'Computer Science & Engineering'
  years_offered int[] not null default array[1,2,3,4], -- which year groups exist
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- PROFILES — one row per auth.users, holds shared identity + role
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         user_role not null,
  full_name    text not null,
  email        text,
  phone        text,
  photo_url    text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- STUDENTS — extends profiles
-- ---------------------------------------------------------------------
create table if not exists public.students (
  id               uuid primary key references public.profiles(id) on delete cascade,
  register_number  text not null unique,
  department_id    uuid not null references public.departments(id),
  year             int not null check (year between 1 and 4),
  section          text,
  two_factor_enabled boolean not null default false,
  created_at       timestamptz not null default now()
);

create index if not exists idx_students_department on public.students(department_id);
create index if not exists idx_students_year on public.students(year);

-- ---------------------------------------------------------------------
-- FACULTY — extends profiles
-- ---------------------------------------------------------------------
create table if not exists public.faculty (
  id              uuid primary key references public.profiles(id) on delete cascade,
  faculty_id      text not null unique,
  department_id   uuid references public.departments(id),
  assigned_years  int[] not null default array[1,2,3,4],
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- ADMINS — extends profiles
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  id                    uuid primary key references public.profiles(id) on delete cascade,
  two_factor_enabled    boolean not null default false,
  -- Which of the 3 parallel tracks this admin login manages (Aptitude /
  -- Technical / Communication). Fixed at account-creation time — an
  -- admin never chooses/switches this in the app; it scopes every
  -- question-bank row and daily test/QR they can create or see. See
  -- policies.sql::current_admin_category() and functions.sql.
  category              test_category not null default 'aptitude',
  created_at            timestamptz not null default now()
);

-- Migration for an already-deployed project (schema.sql is otherwise
-- "create if not exists" only, which doesn't add columns to an existing
-- table) — safe/no-op if the column already exists.
alter table public.admins add column if not exists category test_category not null default 'aptitude';

-- ---------------------------------------------------------------------
-- QUESTION BANK
-- ---------------------------------------------------------------------
create table if not exists public.questions (
  id             uuid primary key default uuid_generate_v4(),
  -- Broad partition (Aptitude / Technical / Communication) — see
  -- test_category above. `subject`/`topic` remain the fine-grained
  -- free-text label *within* a category (e.g. category='technical',
  -- subject='C Programming').
  category       test_category not null default 'aptitude',
  subject        text not null,
  topic          text,
  question_text  text not null,
  option_a       text not null,
  option_b       text not null,
  option_c       text not null,
  option_d       text not null,
  correct_option char(1) not null check (correct_option in ('A','B','C','D')),
  difficulty     question_difficulty not null default 'medium',
  is_active      boolean not null default true,
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.questions add column if not exists category test_category not null default 'aptitude';

create index if not exists idx_questions_subject on public.questions(subject);
create index if not exists idx_questions_difficulty on public.questions(difficulty);
create index if not exists idx_questions_category on public.questions(category);

-- ---------------------------------------------------------------------
-- DAILY TESTS
-- ---------------------------------------------------------------------
create table if not exists public.daily_tests (
  id               uuid primary key default uuid_generate_v4(),
  test_date        date not null,
  -- Which track this test/QR belongs to — a day now has up to 3
  -- daily_tests rows (one per category), each with its own QR, question
  -- set and window. Replaces the old "test_date is globally unique"
  -- constraint below with "unique per (date, category)".
  category         test_category not null default 'aptitude',
  question_count   int not null default 20,
  duration_minutes int not null default 30,
  open_time        timestamptz not null,   -- e.g. 10:00
  close_time       timestamptz not null,   -- e.g. 14:00
  results_time     timestamptz not null,   -- e.g. 15:00
  selection_mode   selection_mode not null default 'auto',
  status           test_status not null default 'draft',
  qr_payload       text,                   -- encoded token embedded in the QR
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  unique (test_date, category)
);

alter table public.daily_tests add column if not exists category test_category not null default 'aptitude';

-- Migration only: an already-deployed project has `test_date unique`
-- (one test per day, no category dimension) — drop that in favor of the
-- composite (test_date, category) unique constraint declared above, so
-- Aptitude/Technical/Communication can each have their own row on the
-- same date. Safe/no-op if already dropped or never existed under this
-- name.
do $$ begin
  alter table public.daily_tests drop constraint if exists daily_tests_test_date_key;
exception when undefined_object then null; end $$;

do $$ begin
  alter table public.daily_tests add constraint daily_tests_test_date_category_key unique (test_date, category);
exception when duplicate_object then null; end $$;

create table if not exists public.daily_test_questions (
  id             uuid primary key default uuid_generate_v4(),
  daily_test_id  uuid not null references public.daily_tests(id) on delete cascade,
  question_id    uuid not null references public.questions(id),
  question_order int not null,
  unique (daily_test_id, question_id),
  unique (daily_test_id, question_order)
);

-- ---------------------------------------------------------------------
-- TEST ATTEMPTS + ANSWERS  (attendance derives from attempt rows)
-- ---------------------------------------------------------------------
create table if not exists public.test_attempts (
  id             uuid primary key default uuid_generate_v4(),
  daily_test_id  uuid not null references public.daily_tests(id) on delete cascade,
  student_id     uuid not null references public.students(id) on delete cascade,
  status         attempt_status not null default 'not_started',
  started_at     timestamptz,
  submitted_at   timestamptz,
  score          int,
  total_questions int,
  synced_offline boolean not null default false, -- true if this attempt was answered offline then synced
  created_at     timestamptz not null default now(),
  unique (daily_test_id, student_id)
);

create index if not exists idx_attempts_test on public.test_attempts(daily_test_id);
create index if not exists idx_attempts_student on public.test_attempts(student_id);
create index if not exists idx_attempts_status on public.test_attempts(status);

create table if not exists public.test_answers (
  id              uuid primary key default uuid_generate_v4(),
  attempt_id      uuid not null references public.test_attempts(id) on delete cascade,
  question_id     uuid not null references public.questions(id),
  selected_option char(1) check (selected_option in ('A','B','C','D')),
  is_correct      boolean,
  answered_at     timestamptz not null default now(),
  client_uuid     text, -- id generated on-device for offline dedupe/upsert
  unique (attempt_id, question_id)
);

create index if not exists idx_answers_attempt on public.test_answers(attempt_id);

-- ---------------------------------------------------------------------
-- RANKINGS — materialized once results are published
-- ---------------------------------------------------------------------
create table if not exists public.rankings (
  id                uuid primary key default uuid_generate_v4(),
  daily_test_id     uuid not null references public.daily_tests(id) on delete cascade,
  student_id        uuid not null references public.students(id) on delete cascade,
  department_id     uuid not null references public.departments(id),
  year              int not null,
  score             int not null,
  rank_overall      int,
  rank_department   int,
  rank_year         int,
  generated_at      timestamptz not null default now(),
  unique (daily_test_id, student_id)
);

create index if not exists idx_rankings_test on public.rankings(daily_test_id);
create index if not exists idx_rankings_dept on public.rankings(department_id);

-- ---------------------------------------------------------------------
-- created_by FK migration — questions.created_by / daily_tests.created_by
-- referenced profiles(id) with the default ON DELETE NO ACTION, so
-- deleting an admin/faculty account that had ever authored a question or
-- generated a test would fail outright with a foreign-key violation
-- instead of completing. SET NULL keeps the question/test itself intact
-- (it doesn't belong to the deleted account, it just loses the "who made
-- this" attribution) and lets the delete actually go through. Named
-- explicitly (Postgres's default autogenerated names match these) so the
-- drop/recreate below is idempotent instead of erroring on re-run.
-- ---------------------------------------------------------------------
do $$ begin
  alter table public.questions drop constraint if exists questions_created_by_fkey;
  alter table public.questions add constraint questions_created_by_fkey
    foreign key (created_by) references public.profiles(id) on delete set null;
exception when others then null; end $$;

do $$ begin
  alter table public.daily_tests drop constraint if exists daily_tests_created_by_fkey;
  alter table public.daily_tests add constraint daily_tests_created_by_fkey
    foreign key (created_by) references public.profiles(id) on delete set null;
exception when others then null; end $$;

-- ---------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists trg_questions_updated on public.questions;
create trigger trg_questions_updated before update on public.questions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Seed departments (safe to re-run)
-- ---------------------------------------------------------------------
insert into public.departments (code, name) values
  ('AIML', 'Artificial Intelligence & Machine Learning'),
  ('CSE',  'Computer Science & Engineering'),
  ('IT',   'Information Technology'),
  ('ECE',  'Electronics & Communication Engineering'),
  ('BCA',  'Bachelor of Computer Applications'),
  ('MCA',  'Master of Computer Applications')
on conflict (code) do nothing;
