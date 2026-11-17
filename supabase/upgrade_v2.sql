-- =====================================================================
-- AptiQR — upgrade_v2.sql
-- Run AFTER schema.sql, auth_trigger.sql, auth_helpers.sql, policies.sql
-- and functions.sql. Safe to re-run (idempotent).
--
-- Adds: rotating QR + geofence + device binding, server-side time
-- enforcement, integrity event log, audit log, auto open/close/publish
-- (pg_cron), recurring test templates, XP/streaks/badges/leaderboard,
-- practice mode (adaptive), topic analytics, at-risk list, trends,
-- placement-readiness score, review-with-explanations, push outbox,
-- lookup rate limiting, faculty answer-key lockdown.
-- =====================================================================

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------
-- 0. Column additions
-- ---------------------------------------------------------------------
alter table public.questions add column if not exists explanation text;
alter table public.questions add column if not exists ai_generated boolean not null default false;
alter table public.questions add column if not exists source text not null default 'manual';
create index if not exists idx_questions_trgm on public.questions using gin (question_text gin_trgm_ops);

alter table public.daily_tests add column if not exists qr_secret text not null default replace(gen_random_uuid()::text, '-', '');
alter table public.daily_tests add column if not exists qr_rotating boolean not null default true;
alter table public.daily_tests add column if not exists geo_lat double precision;
alter table public.daily_tests add column if not exists geo_lng double precision;
alter table public.daily_tests add column if not exists geo_radius_m int;
alter table public.daily_tests add column if not exists auto_publish boolean not null default true;

alter table public.test_attempts add column if not exists xp_awarded boolean not null default false;
alter table public.test_attempts add column if not exists device_id text;

-- ---------------------------------------------------------------------
-- 1. Internal tables (no direct client access; read via RPCs)
-- ---------------------------------------------------------------------
create table if not exists public.student_devices (
  student_id uuid primary key references public.students(id) on delete cascade,
  device_id  text not null,
  bound_at   timestamptz not null default now()
);

create table if not exists public.integrity_events (
  id             uuid primary key default uuid_generate_v4(),
  attempt_id     uuid not null references public.test_attempts(id) on delete cascade,
  student_id     uuid not null references public.students(id) on delete cascade,
  daily_test_id  uuid not null references public.daily_tests(id) on delete cascade,
  event_type     text not null check (event_type in
    ('app_background','screenshot_attempt','device_mismatch','location_mismatch','copy_attempt','other')),
  detail         text,
  created_at     timestamptz not null default now()
);
create index if not exists idx_integrity_test on public.integrity_events(daily_test_id);
create index if not exists idx_integrity_attempt on public.integrity_events(attempt_id);

create table if not exists public.audit_log (
  id         bigserial primary key,
  actor      uuid,
  action     text not null,
  table_name text not null,
  row_id     text,
  detail     jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_audit_created on public.audit_log(created_at desc);

create table if not exists public.student_stats (
  student_id      uuid primary key references public.students(id) on delete cascade,
  xp              int  not null default 0,
  current_streak  int  not null default 0,
  best_streak     int  not null default 0,
  tests_taken     int  not null default 0,
  last_test_date  date
);

create table if not exists public.xp_log (
  id             bigserial primary key,
  student_id     uuid not null references public.students(id) on delete cascade,
  daily_test_id  uuid references public.daily_tests(id) on delete set null,
  xp             int not null,
  created_at     timestamptz not null default now()
);
create index if not exists idx_xp_log_student on public.xp_log(student_id, created_at desc);

create table if not exists public.badges (
  code        text primary key,
  name        text not null,
  description text not null,
  icon        text not null default 'emoji_events'
);

create table if not exists public.student_badges (
  student_id uuid not null references public.students(id) on delete cascade,
  badge_code text not null references public.badges(code),
  earned_at  timestamptz not null default now(),
  primary key (student_id, badge_code)
);

insert into public.badges (code, name, description, icon) values
  ('first_test', 'First Steps',   'Completed your first daily test', 'flag'),
  ('streak_3',   'On a Roll',     '3 test days in a row',            'local_fire_department'),
  ('streak_7',   'Unstoppable',   '7 test days in a row',            'whatshot'),
  ('tests_10',   'Regular',       'Completed 10 tests',              'verified'),
  ('perfect',    'Perfect Score', 'Answered every question correctly','stars'),
  ('top3',       'Podium',        'Finished in the overall top 3',   'emoji_events')
on conflict (code) do nothing;

create table if not exists public.practice_answers (
  id               bigserial primary key,
  student_id       uuid not null references public.students(id) on delete cascade,
  question_id      uuid not null references public.questions(id) on delete cascade,
  selected_option  char(1) not null check (selected_option in ('A','B','C','D')),
  is_correct       boolean not null,
  created_at       timestamptz not null default now()
);
create index if not exists idx_practice_student on public.practice_answers(student_id, created_at desc);

create table if not exists public.test_templates (
  id                uuid primary key default uuid_generate_v4(),
  category          test_category not null,
  name              text not null default '',
  weekdays          int[] not null default array[1,2,3,4,5],  -- ISO: 1=Mon .. 7=Sun
  question_count    int  not null default 20,
  duration_minutes  int  not null default 30,
  open_time         time not null default '10:00',
  close_time        time not null default '14:00',
  results_time      time not null default '15:00',
  geo_lat           double precision,
  geo_lng           double precision,
  geo_radius_m      int,
  is_active         boolean not null default true,
  created_by        uuid references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now()
);

create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  platform    text,
  updated_at  timestamptz not null default now()
);

create table if not exists public.push_outbox (
  id          bigserial primary key,
  audience    jsonb not null,           -- {"role":"student"} | {"user_ids":["..."]}
  title       text not null,
  body        text not null,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);

create table if not exists public.app_config (
  key   text primary key,
  value text not null
);

create table if not exists public.lookup_attempts (
  id         bigserial primary key,
  ip         text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_lookup_attempts on public.lookup_attempts(ip, created_at);

-- RLS: enable everywhere, lock internal tables completely.
do $$
declare t text;
begin
  foreach t in array array[
    'student_devices','integrity_events','audit_log','student_stats','xp_log','badges',
    'student_badges','practice_answers','test_templates','device_tokens','push_outbox',
    'app_config','lookup_attempts'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

grant select on public.badges to authenticated;
drop policy if exists "badges_select" on public.badges;
create policy "badges_select" on public.badges for select using (auth.uid() is not null);

grant select on public.audit_log to authenticated;
drop policy if exists "audit_select_admin" on public.audit_log;
create policy "audit_select_admin" on public.audit_log for select using (public.is_admin());

grant select, insert, update, delete on public.test_templates to authenticated;
drop policy if exists "templates_admin_all" on public.test_templates;
create policy "templates_admin_all" on public.test_templates for all
  using (public.is_admin() and category = public.current_admin_category())
  with check (public.is_admin() and category = public.current_admin_category());

-- ---------------------------------------------------------------------
-- 2. Faculty can no longer read the question bank directly (answer key).
--    Faculty see papers only through fetch_test_questions (no key).
-- ---------------------------------------------------------------------
drop policy if exists "questions_select_admin_faculty" on public.questions;
drop policy if exists "questions_select_admin" on public.questions;
create policy "questions_select_admin" on public.questions
  for select using (public.is_admin() and category = public.current_admin_category());

-- ---------------------------------------------------------------------
-- 3. Audit triggers
-- ---------------------------------------------------------------------
create or replace function public.audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_row jsonb;
begin
  if TG_OP = 'DELETE' then v_row := to_jsonb(OLD); else v_row := to_jsonb(NEW); end if;
  insert into public.audit_log (actor, action, table_name, row_id, detail)
  values (
    auth.uid(), TG_OP, TG_TABLE_NAME, v_row->>'id',
    case when TG_TABLE_NAME = 'profiles'
         then jsonb_build_object('role', v_row->>'role', 'is_active', v_row->>'is_active')
         else jsonb_build_object('summary', left(v_row::text, 500)) end
  );
  return null;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['daily_tests','questions','admins','test_templates'] loop
    execute format('drop trigger if exists trg_audit on public.%I', t);
    execute format('create trigger trg_audit after insert or update or delete on public.%I
                    for each row execute function public.audit_trigger()', t);
  end loop;
end $$;

drop trigger if exists trg_audit on public.profiles;
create trigger trg_audit after update of is_active, role on public.profiles
  for each row execute function public.audit_trigger();

-- ---------------------------------------------------------------------
-- 4. Rotating QR, geofence, device binding
-- ---------------------------------------------------------------------
create or replace function public._qr_token(p_secret text, p_window bigint)
returns text language sql immutable as $$
  select upper(substr(md5(p_secret || ':' || p_window::text), 1, 8));
$$;

create or replace function public._distance_m(lat1 double precision, lng1 double precision,
                                              lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  )));
$$;

-- Faculty/admin screen polls this to render the QR.
drop function if exists public.current_qr_token(uuid);
create or replace function public.current_qr_token(p_daily_test_id uuid)
returns table (token text, seconds_left int, rotating boolean)
language plpgsql security definer stable set search_path = public as $$
declare
  v_t public.daily_tests;
  v_epoch bigint;
begin
  if not (public.is_admin() or public.is_faculty()) then
    raise exception 'Not authorized';
  end if;
  select * into v_t from public.daily_tests where id = p_daily_test_id;
  if v_t.id is null then raise exception 'Test not found'; end if;
  if public.is_admin() and v_t.category is distinct from public.current_admin_category() then
    raise exception 'Not authorized';
  end if;

  if not v_t.qr_rotating then
    return query select coalesce(v_t.qr_payload, v_t.id::text), 0, false;
    return;
  end if;

  v_epoch := floor(extract(epoch from now()))::bigint;
  return query select public._qr_token(v_t.qr_secret, v_epoch / 30), (30 - (v_epoch % 30))::int, true;
end;
$$;
grant execute on function public.current_qr_token(uuid) to authenticated;

create or replace function public._verify_qr(p_test public.daily_tests, p_token text)
returns boolean language plpgsql stable set search_path = public as $$
declare v_win bigint; i int;
begin
  if p_token is null or length(trim(p_token)) = 0 then return false; end if;
  if not p_test.qr_rotating then
    return trim(p_token) = coalesce(p_test.qr_payload, p_test.id::text);
  end if;
  v_win := floor(extract(epoch from now()))::bigint / 30;
  -- accept the current window and the previous two (~60-90 s of slack)
  for i in 0..2 loop
    if upper(trim(p_token)) = public._qr_token(p_test.qr_secret, v_win - i) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

create or replace function public._check_device(p_device_id text)
returns void language plpgsql security definer set search_path = public as $$
declare v_bound text;
begin
  if p_device_id is null or length(p_device_id) < 8 then
    raise exception 'This device could not be identified. Update the app and try again.';
  end if;
  select device_id into v_bound from public.student_devices where student_id = auth.uid();
  if v_bound is null then
    insert into public.student_devices (student_id, device_id) values (auth.uid(), p_device_id)
    on conflict (student_id) do nothing;
  elsif v_bound <> p_device_id then
    raise exception 'This account is linked to a different phone. Ask your faculty to reset your device.';
  end if;
end;
$$;

create or replace function public.reset_student_device(p_student_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_admin() or (public.is_faculty() and exists (
        select 1 from public.students s
        where s.id = p_student_id and s.department_id = public.current_faculty_department()))) then
    raise exception 'Not authorized';
  end if;
  delete from public.student_devices where student_id = p_student_id;
end;
$$;
grant execute on function public.reset_student_device(uuid) to authenticated;

drop function if exists public.start_test_attempt(uuid);
create or replace function public.start_test_attempt(
  p_daily_test_id uuid,
  p_qr_token text default null,
  p_device_id text default null,
  p_lat double precision default null,
  p_lng double precision default null
)
returns public.test_attempts
language plpgsql security definer set search_path = public as $$
declare
  v_attempt public.test_attempts;
  v_test public.daily_tests;
begin
  select * into v_test from public.daily_tests where id = p_daily_test_id;
  if v_test.id is null then raise exception 'Test not found'; end if;
  if now() < v_test.open_time or now() > v_test.close_time then
    raise exception 'Test is not open right now';
  end if;

  perform public._check_device(p_device_id);

  -- One phone, one student per test: stops proxy attendance where a single
  -- phone is passed around and used to sign several accounts into a test.
  if exists (select 1 from public.test_attempts o
             where o.daily_test_id = p_daily_test_id and o.device_id = p_device_id
               and o.student_id <> auth.uid()) then
    raise exception 'This phone was already used by another student for this test.';
  end if;

  select * into v_attempt from public.test_attempts
    where daily_test_id = p_daily_test_id and student_id = auth.uid();

  if v_attempt.id is not null and v_attempt.status = 'submitted' then
    raise exception 'You have already submitted this test';
  end if;
  if v_attempt.id is not null and v_attempt.status = 'absent' then
    raise exception 'This attempt has been closed';
  end if;

  -- Resuming an in-progress attempt needs no new QR; a fresh start does.
  if v_attempt.id is null or v_attempt.status = 'not_started' then
    if not public._verify_qr(v_test, p_qr_token) then
      raise exception 'Invalid or expired QR code. Scan the code currently shown by your faculty.';
    end if;
    if v_test.geo_lat is not null and v_test.geo_lng is not null and v_test.geo_radius_m is not null then
      if p_lat is null or p_lng is null then
        raise exception 'Location is required for this test. Turn on location and try again.';
      end if;
      if public._distance_m(v_test.geo_lat, v_test.geo_lng, p_lat, p_lng) > v_test.geo_radius_m then
        raise exception 'You are not at the test location.';
      end if;
    end if;
  end if;

  if v_attempt.id is null then
    insert into public.test_attempts (daily_test_id, student_id, status, started_at, total_questions, device_id)
    values (p_daily_test_id, auth.uid(), 'in_progress', now(), v_test.question_count, p_device_id)
    returning * into v_attempt;
  elsif v_attempt.status = 'not_started' then
    update public.test_attempts set status = 'in_progress', started_at = now(), device_id = p_device_id
      where id = v_attempt.id returning * into v_attempt;
  end if;

  return v_attempt;
end;
$$;
grant execute on function public.start_test_attempt(uuid, text, text, double precision, double precision) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Server-side time enforcement
--    Deadline = started_at + duration + 60 s grace. Offline replay is
--    honoured via p_answered_at (client time, clamped to server time),
--    but nothing is accepted later than deadline + 30 min of real time.
-- ---------------------------------------------------------------------
drop function if exists public.submit_answer(uuid, uuid, character, text);
create or replace function public.submit_answer(
  p_attempt_id uuid,
  p_question_id uuid,
  p_selected_option char(1),
  p_client_uuid text default null,
  p_answered_at timestamptz default null
)
returns public.test_answers
language plpgsql security definer set search_path = public as $$
declare
  v_answer public.test_answers;
  v_correct char(1);
  v_att public.test_attempts;
  v_dur int;
  v_deadline timestamptz;
  v_effective timestamptz;
begin
  select * into v_att from public.test_attempts where id = p_attempt_id;
  if v_att.id is null or v_att.student_id <> auth.uid() then raise exception 'Not your attempt'; end if;
  if v_att.status <> 'in_progress' then raise exception 'Attempt already closed'; end if;

  if not exists (select 1 from public.daily_test_questions
                 where daily_test_id = v_att.daily_test_id and question_id = p_question_id) then
    raise exception 'That question is not part of this test';
  end if;

  select duration_minutes into v_dur from public.daily_tests where id = v_att.daily_test_id;
  v_deadline := v_att.started_at + make_interval(mins => v_dur) + interval '60 seconds';
  v_effective := greatest(v_att.started_at, least(coalesce(p_answered_at, now()), now()));

  if v_effective > v_deadline or now() > v_deadline + interval '30 minutes' then
    raise exception 'Time is up for this test';
  end if;

  select correct_option into v_correct from public.questions where id = p_question_id;

  insert into public.test_answers (attempt_id, question_id, selected_option, is_correct, client_uuid, answered_at)
  values (p_attempt_id, p_question_id, p_selected_option, (p_selected_option = v_correct), p_client_uuid, v_effective)
  on conflict (attempt_id, question_id) do update
    set selected_option = excluded.selected_option,
        is_correct = excluded.is_correct,
        answered_at = excluded.answered_at,
        client_uuid = excluded.client_uuid
  returning * into v_answer;

  return v_answer;
end;
$$;
grant execute on function public.submit_answer(uuid, uuid, character, text, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Integrity events
-- ---------------------------------------------------------------------
create or replace function public.log_integrity_event(p_attempt_id uuid, p_event_type text, p_detail text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_att public.test_attempts; v_n int;
begin
  select * into v_att from public.test_attempts where id = p_attempt_id;
  if v_att.id is null or v_att.student_id <> auth.uid() then raise exception 'Not your attempt'; end if;
  select count(*) into v_n from public.integrity_events where attempt_id = p_attempt_id;
  if v_n >= 200 then return; end if;
  insert into public.integrity_events (attempt_id, student_id, daily_test_id, event_type, detail)
  values (p_attempt_id, v_att.student_id, v_att.daily_test_id,
          case when p_event_type in ('app_background','screenshot_attempt','device_mismatch','location_mismatch','copy_attempt')
               then p_event_type else 'other' end,
          left(p_detail, 300));
end;
$$;
grant execute on function public.log_integrity_event(uuid, text, text) to authenticated;

create or replace function public.fetch_integrity_summary(p_daily_test_id uuid)
returns table (
  student_id uuid, register_number text, full_name text, department_id uuid,
  total_events int, background_events int, last_event timestamptz
)
language plpgsql security definer stable set search_path = public as $$
begin
  if not (public.is_admin() or public.is_faculty()) then raise exception 'Not authorized'; end if;
  if public.is_admin() and not exists (
       select 1 from public.daily_tests dt
       where dt.id = p_daily_test_id and dt.category = public.current_admin_category()) then
    raise exception 'Not authorized';
  end if;
  return query
  select e.student_id, s.register_number, p.full_name, s.department_id,
         count(*)::int,
         (count(*) filter (where e.event_type = 'app_background'))::int,
         max(e.created_at)
  from public.integrity_events e
  join public.students s on s.id = e.student_id
  join public.profiles p on p.id = s.id
  where e.daily_test_id = p_daily_test_id
    and (public.is_admin() or s.department_id = public.current_faculty_department())
  group by e.student_id, s.register_number, p.full_name, s.department_id
  order by count(*) desc;
end;
$$;
grant execute on function public.fetch_integrity_summary(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Publishing: shared core (also used by the scheduler), fair handling
--    of in-progress attempts, then XP/streaks/badges.
-- ---------------------------------------------------------------------
create or replace function public._award_progress(p_daily_test_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_test public.daily_tests;
  v_prev date;
  r record;
  v_xp int;
begin
  select * into v_test from public.daily_tests where id = p_daily_test_id;
  select max(test_date) into v_prev from public.daily_tests where test_date < v_test.test_date;

  for r in
    select a.id as attempt_id, a.student_id, coalesce(a.score, 0) as score,
           coalesce(nullif(a.total_questions, 0), v_test.question_count) as total,
           rk.rank_overall
    from public.test_attempts a
    left join public.rankings rk on rk.daily_test_id = a.daily_test_id and rk.student_id = a.student_id
    where a.daily_test_id = p_daily_test_id and a.status = 'submitted' and a.xp_awarded = false
  loop
    v_xp := 20 + r.score * 10 + case
      when r.rank_overall = 1 then 50
      when r.rank_overall <= 3 then 30
      when r.rank_overall <= 10 then 10 else 0 end;

    insert into public.student_stats (student_id) values (r.student_id) on conflict do nothing;

    update public.student_stats s set
      xp = s.xp + v_xp,
      tests_taken = s.tests_taken + 1,
      current_streak = case
        when s.last_test_date = v_test.test_date then s.current_streak
        when v_prev is not null and s.last_test_date = v_prev then s.current_streak + 1
        else 1 end,
      last_test_date = greatest(coalesce(s.last_test_date, v_test.test_date), v_test.test_date)
    where s.student_id = r.student_id;

    update public.student_stats s set best_streak = greatest(s.best_streak, s.current_streak)
      where s.student_id = r.student_id;

    insert into public.xp_log (student_id, daily_test_id, xp) values (r.student_id, p_daily_test_id, v_xp);

    insert into public.student_badges (student_id, badge_code)
    select r.student_id, b.code from (
      select 'first_test'::text as code, true as ok
      union all select 'streak_3', s.current_streak >= 3 from public.student_stats s where s.student_id = r.student_id
      union all select 'streak_7', s.current_streak >= 7 from public.student_stats s where s.student_id = r.student_id
      union all select 'tests_10', s.tests_taken >= 10 from public.student_stats s where s.student_id = r.student_id
      union all select 'perfect', (r.total > 0 and r.score = r.total)
      union all select 'top3', (r.rank_overall is not null and r.rank_overall <= 3)
    ) b where b.ok
    on conflict do nothing;

    update public.test_attempts set xp_awarded = true where id = r.attempt_id;
  end loop;
end;
$$;

create or replace function public._publish_results_core(p_daily_test_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_cat test_category;
begin
  -- Students who answered something but never tapped Submit (app killed,
  -- offline) get their answers scored instead of being wiped to absent.
  update public.test_attempts a set
    status = 'submitted', submitted_at = coalesce(a.submitted_at, now()),
    score = coalesce((select count(*) filter (where x.is_correct) from public.test_answers x where x.attempt_id = a.id), 0)
  where a.daily_test_id = p_daily_test_id and a.status = 'in_progress'
    and exists (select 1 from public.test_answers x where x.attempt_id = a.id);

  update public.test_attempts set status = 'absent'
    where daily_test_id = p_daily_test_id and status in ('not_started', 'in_progress');

  insert into public.test_attempts (daily_test_id, student_id, status, total_questions)
  select p_daily_test_id, s.id, 'absent', dt.question_count
  from public.students s
  join public.profiles p on p.id = s.id
  cross join public.daily_tests dt
  where dt.id = p_daily_test_id and p.is_active = true
    and not exists (select 1 from public.test_attempts a
                    where a.daily_test_id = p_daily_test_id and a.student_id = s.id);

  delete from public.rankings where daily_test_id = p_daily_test_id;

  insert into public.rankings (daily_test_id, student_id, department_id, year, score, rank_overall, rank_department, rank_year)
  select a.daily_test_id, a.student_id, s.department_id, s.year, coalesce(a.score, 0),
         rank() over (order by coalesce(a.score, 0) desc),
         rank() over (partition by s.department_id order by coalesce(a.score, 0) desc),
         rank() over (partition by s.year order by coalesce(a.score, 0) desc)
  from public.test_attempts a
  join public.students s on s.id = a.student_id
  where a.daily_test_id = p_daily_test_id and a.status = 'submitted';

  update public.daily_tests set status = 'published' where id = p_daily_test_id
    returning category into v_cat;

  perform public._award_progress(p_daily_test_id);

  insert into public.push_outbox (audience, title, body)
  values ('{"role":"student"}'::jsonb, 'Results are out',
          initcap(v_cat::text) || ' test results are published. Check your rank!');
end;
$$;

create or replace function public.publish_results(p_daily_test_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_category test_category;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  select category into v_category from public.daily_tests where id = p_daily_test_id;
  if v_category is null then raise exception 'Test not found'; end if;
  if v_category is distinct from public.current_admin_category() then
    raise exception 'You can only publish results for tests in your own category';
  end if;
  perform public._publish_results_core(p_daily_test_id);
end;
$$;

revoke execute on function public._publish_results_core(uuid) from public, anon, authenticated;
revoke execute on function public._award_progress(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 8. Scheduler: templates -> open -> close -> publish (+ push, cleanup)
-- ---------------------------------------------------------------------
create or replace function public.auto_generate_from_templates()
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_now time := (now() at time zone 'Asia/Kolkata')::time;
  v_avail int; v_test_id uuid; v_qid uuid; v_order int;
begin
  for r in
    select * from public.test_templates t
    where t.is_active
      and extract(isodow from v_today)::int = any (t.weekdays)
      and v_now >= time '06:00'
      and not exists (select 1 from public.daily_tests d where d.test_date = v_today and d.category = t.category)
  loop
    select count(*) into v_avail from public.questions q where q.is_active and q.category = r.category;
    continue when v_avail < r.question_count;

    insert into public.daily_tests (
      test_date, category, question_count, duration_minutes, open_time, close_time, results_time,
      selection_mode, status, qr_payload, created_by, geo_lat, geo_lng, geo_radius_m)
    values (
      v_today, r.category, r.question_count, r.duration_minutes,
      (v_today + r.open_time) at time zone 'Asia/Kolkata',
      (v_today + r.close_time) at time zone 'Asia/Kolkata',
      (v_today + r.results_time) at time zone 'Asia/Kolkata',
      'auto', 'scheduled', replace(gen_random_uuid()::text, '-', ''), r.created_by,
      r.geo_lat, r.geo_lng, r.geo_radius_m)
    returning id into v_test_id;

    v_order := 1;
    for v_qid in select q.id from public.questions q
                 where q.is_active and q.category = r.category order by random() limit r.question_count
    loop
      insert into public.daily_test_questions (daily_test_id, question_id, question_order)
      values (v_test_id, v_qid, v_order);
      v_order := v_order + 1;
    end loop;
  end loop;
end;
$$;

create or replace function public.auto_advance_tests()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  perform public.auto_generate_from_templates();

  with o as (
    update public.daily_tests set status = 'open'
    where status = 'scheduled' and now() >= open_time and now() < close_time
    returning category
  )
  insert into public.push_outbox (audience, title, body)
  select '{"role":"student"}'::jsonb, 'Test is open',
         initcap(o.category::text) || ' test is open now. Scan the QR to start.'
  from o;

  update public.daily_tests set status = 'closed'
    where status in ('scheduled', 'open') and now() >= close_time;

  for r in select id from public.daily_tests
           where status in ('open', 'closed') and auto_publish and now() >= results_time
  loop
    perform public._publish_results_core(r.id);
  end loop;

  delete from public.lookup_attempts where created_at < now() - interval '1 day';
  delete from public.push_outbox where sent_at is not null and sent_at < now() - interval '7 days';
end;
$$;
revoke execute on function public.auto_advance_tests() from public, anon, authenticated;
revoke execute on function public.auto_generate_from_templates() from public, anon, authenticated;

create or replace function public.trigger_push_delivery()
returns void language plpgsql security definer set search_path = public as $$
declare v_url text; v_secret text;
begin
  if not exists (select 1 from public.push_outbox where sent_at is null) then return; end if;
  select value into v_url from public.app_config where key = 'push_function_url';
  select value into v_secret from public.app_config where key = 'push_secret';
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(url := v_url,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
                        body := '{}'::jsonb);
exception when others then
  null; -- pg_net not enabled yet: outbox simply keeps waiting
end;
$$;
revoke execute on function public.trigger_push_delivery() from public, anon, authenticated;

do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be enabled. Enable it under Database > Extensions, then re-run this block.';
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('aptiqr-advance', 'aptiqr-push');
    perform cron.schedule('aptiqr-advance', '* * * * *', 'select public.auto_advance_tests()');
    perform cron.schedule('aptiqr-push',    '* * * * *', 'select public.trigger_push_delivery()');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 9. Push tokens
-- ---------------------------------------------------------------------
create or replace function public.register_push_token(p_token text, p_platform text default null)
returns void language sql security definer set search_path = public as $$
  insert into public.device_tokens (token, user_id, platform, updated_at)
  select p_token, auth.uid(), p_platform, now() where auth.uid() is not null
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
$$;
create or replace function public.unregister_push_token(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------
-- 10. Rate-limited login lookups
-- ---------------------------------------------------------------------
create or replace function public._throttle_lookup()
returns void language plpgsql security definer set search_path = public as $$
declare v_ip text; v_n int;
begin
  v_ip := coalesce(nullif(split_part(coalesce(
            (nullif(current_setting('request.headers', true), ''))::json->>'x-forwarded-for', ''), ',', 1), ''), 'unknown');
  select count(*) into v_n from public.lookup_attempts
    where ip = v_ip and created_at > now() - interval '1 minute';
  if v_n >= 12 then
    raise exception 'Too many attempts. Please wait a minute and try again.';
  end if;
  insert into public.lookup_attempts (ip) values (v_ip);
end;
$$;

create or replace function public.lookup_student_login_email(p_register_number text)
returns text language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  perform public._throttle_lookup();
  select p.email into v_email from public.students s join public.profiles p on p.id = s.id
   where s.register_number = p_register_number and p.is_active = true limit 1;
  return v_email;
end;
$$;

create or replace function public.lookup_faculty_login_email(p_identifier text)
returns text language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  perform public._throttle_lookup();
  select p.email into v_email from public.faculty f join public.profiles p on p.id = f.id
   where (f.faculty_id = p_identifier or p.email = p_identifier) and p.is_active = true limit 1;
  return v_email;
end;
$$;
grant execute on function public.lookup_student_login_email(text) to anon, authenticated;
grant execute on function public.lookup_faculty_login_email(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 11. Student: stats, leaderboard, review, topic stats, readiness
-- ---------------------------------------------------------------------
create or replace function public.my_stats()
returns jsonb language sql security definer stable set search_path = public as $$
  select jsonb_build_object(
    'xp', coalesce(st.xp, 0),
    'level', floor(sqrt(coalesce(st.xp, 0) / 100.0))::int + 1,
    'current_streak', coalesce(st.current_streak, 0),
    'best_streak', coalesce(st.best_streak, 0),
    'tests_taken', coalesce(st.tests_taken, 0),
    'badges', coalesce((
      select jsonb_agg(jsonb_build_object('code', b.code, 'name', b.name, 'description', b.description,
                                          'icon', b.icon, 'earned_at', sb.earned_at) order by sb.earned_at)
      from public.student_badges sb join public.badges b on b.code = sb.badge_code
      where sb.student_id = auth.uid()), '[]'::jsonb),
    'all_badges', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'description', description, 'icon', icon)) from public.badges)
  )
  from (select 1) one
  left join public.student_stats st on st.student_id = auth.uid();
$$;
grant execute on function public.my_stats() to authenticated;

create or replace function public.fetch_leaderboard(p_scope text default 'overall', p_period text default 'all', p_limit int default 20)
returns table (lb_rank int, student_id uuid, full_name text, department_code text, year int, xp bigint, is_me boolean)
language sql security definer stable set search_path = public as $$
  with me as (select s.department_id, s.year from public.students s where s.id = auth.uid()),
  base as (
    select s.id, p.full_name, d.code as dcode, s.year,
      case when p_period = 'week'
           then coalesce((select sum(l.xp) from public.xp_log l where l.student_id = s.id and l.created_at >= now() - interval '7 days'), 0)
           else coalesce(st.xp, 0) end as xpv
    from public.students s
    join public.profiles p on p.id = s.id
    join public.departments d on d.id = s.department_id
    left join public.student_stats st on st.student_id = s.id
    where auth.uid() is not null and p.is_active
      and (p_scope = 'overall'
        or (p_scope = 'department' and s.department_id = coalesce((select department_id from me), public.current_faculty_department()))
        or (p_scope = 'year' and s.year = (select year from me)))
  )
  select (rank() over (order by xpv desc))::int, id, full_name, dcode, year, xpv::bigint, id = auth.uid()
  from base where xpv > 0
  order by 1, full_name
  limit least(p_limit, 100);
$$;
grant execute on function public.fetch_leaderboard(text, text, int) to authenticated;

create or replace function public.fetch_review(p_daily_test_id uuid)
returns table (
  question_order int, question_id uuid, subject text, question_text text,
  option_a text, option_b text, option_c text, option_d text,
  correct_option char(1), explanation text, selected_option char(1), is_correct boolean
)
language plpgsql security definer stable set search_path = public as $$
#variable_conflict use_column
begin
  if not exists (select 1 from public.daily_tests dt where dt.id = p_daily_test_id and dt.status = 'published') then
    raise exception 'Review is available after results are published.';
  end if;
  if not (public.is_admin() or public.is_faculty() or exists (
        select 1 from public.test_attempts a
        where a.daily_test_id = p_daily_test_id and a.student_id = auth.uid() and a.status = 'submitted')) then
    raise exception 'Not authorized';
  end if;
  return query
  select dtq.question_order, q.id, q.subject, q.question_text, q.option_a, q.option_b, q.option_c, q.option_d,
         q.correct_option, q.explanation, ans.selected_option, ans.is_correct
  from public.daily_test_questions dtq
  join public.questions q on q.id = dtq.question_id
  left join public.test_attempts t on t.daily_test_id = dtq.daily_test_id and t.student_id = auth.uid()
  left join public.test_answers ans on ans.attempt_id = t.id and ans.question_id = q.id
  where dtq.daily_test_id = p_daily_test_id
  order by dtq.question_order;
end;
$$;
grant execute on function public.fetch_review(uuid) to authenticated;

create or replace function public.student_topic_stats()
returns table (category text, subject text, attempted int, correct int)
language sql security definer stable set search_path = public as $$
  select q.category::text, q.subject, count(*)::int, (count(*) filter (where x.is_correct))::int
  from (
    select a.question_id, a.is_correct
    from public.test_answers a join public.test_attempts t on t.id = a.attempt_id
    where t.student_id = auth.uid() and t.status = 'submitted'
    union all
    select pa.question_id, pa.is_correct from public.practice_answers pa where pa.student_id = auth.uid()
  ) x
  join public.questions q on q.id = x.question_id
  group by q.category, q.subject
  order by (count(*) filter (where x.is_correct))::float / count(*) asc;
$$;
grant execute on function public.student_topic_stats() to authenticated;

create or replace function public.placement_readiness(p_student_id uuid default null)
returns jsonb language plpgsql security definer stable set search_path = public as $$
declare
  v_sid uuid := coalesce(p_student_id, auth.uid());
  v_apt float; v_tech float; v_comm float; v_att float; v_score float; v_band text;
begin
  if v_sid is null then raise exception 'Not authorized'; end if;
  if v_sid <> auth.uid() and not (public.is_admin() or (public.is_faculty() and exists (
       select 1 from public.students s where s.id = v_sid and s.department_id = public.current_faculty_department()))) then
    raise exception 'Not authorized';
  end if;

  select coalesce(avg(pct), 0) into v_apt from (
    select 100.0 * t.score / nullif(t.total_questions, 0) as pct
    from public.test_attempts t join public.daily_tests d on d.id = t.daily_test_id
    where t.student_id = v_sid and t.status = 'submitted' and d.category = 'aptitude'
    order by d.test_date desc limit 10) x;
  select coalesce(avg(pct), 0) into v_tech from (
    select 100.0 * t.score / nullif(t.total_questions, 0) as pct
    from public.test_attempts t join public.daily_tests d on d.id = t.daily_test_id
    where t.student_id = v_sid and t.status = 'submitted' and d.category = 'technical'
    order by d.test_date desc limit 10) x;
  select coalesce(avg(pct), 0) into v_comm from (
    select 100.0 * t.score / nullif(t.total_questions, 0) as pct
    from public.test_attempts t join public.daily_tests d on d.id = t.daily_test_id
    where t.student_id = v_sid and t.status = 'submitted' and d.category = 'communication'
    order by d.test_date desc limit 10) x;
  select coalesce(100.0 * count(*) filter (where status = 'submitted') / nullif(count(*), 0), 0) into v_att from (
    select t.status from public.test_attempts t join public.daily_tests d on d.id = t.daily_test_id
    where t.student_id = v_sid and d.status = 'published' order by d.test_date desc limit 20) y;

  v_score := 0.85 * (0.4 * v_apt + 0.4 * v_tech + 0.2 * v_comm) + 0.15 * v_att;
  v_band := case when v_score >= 75 then 'Ready' when v_score >= 55 then 'Almost there' else 'Needs work' end;
  return jsonb_build_object('score', round(v_score::numeric, 1), 'band', v_band,
    'aptitude', round(v_apt::numeric, 1), 'technical', round(v_tech::numeric, 1),
    'communication', round(v_comm::numeric, 1), 'attendance', round(v_att::numeric, 1));
end;
$$;
grant execute on function public.placement_readiness(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 12. Practice mode (adaptive difficulty, weak-topic focus)
--     Never serves questions from tests that are not yet published.
-- ---------------------------------------------------------------------
create or replace function public.practice_next_question(
  p_category test_category,
  p_weak_only boolean default false,
  p_exclude uuid[] default '{}'
)
returns table (
  question_id uuid, subject text, topic text, question_text text,
  option_a text, option_b text, option_c text, option_d text, difficulty text
)
language plpgsql security definer stable set search_path = public as $$
#variable_conflict use_column
declare v_acc float; v_target text; v_weak text[];
begin
  if auth.uid() is null then raise exception 'Not authorized'; end if;

  select avg(case when pa.is_correct then 1.0 else 0.0 end) into v_acc from (
    select x.is_correct from public.practice_answers x join public.questions qq on qq.id = x.question_id
    where x.student_id = auth.uid() and qq.category = p_category order by x.created_at desc limit 10) pa;
  v_target := case when v_acc is null then 'medium' when v_acc >= 0.8 then 'hard' when v_acc < 0.5 then 'easy' else 'medium' end;

  if p_weak_only then
    select array_agg(w.subject) into v_weak from (
      select ts.subject from public.student_topic_stats() ts
      where ts.category = p_category::text and ts.attempted >= 3
      order by ts.correct::float / ts.attempted asc limit 3) w;
  end if;

  return query
  select q.id, q.subject, q.topic, q.question_text, q.option_a, q.option_b, q.option_c, q.option_d, q.difficulty::text
  from public.questions q
  where q.is_active and q.category = p_category
    and not (q.id = any (p_exclude))
    and (v_weak is null or q.subject = any (v_weak))
    and not exists (select 1 from public.daily_test_questions dq join public.daily_tests dt on dt.id = dq.daily_test_id
                    where dq.question_id = q.id and dt.status <> 'published')
  order by (q.difficulty::text = v_target) desc, random()
  limit 1;
end;
$$;
grant execute on function public.practice_next_question(test_category, boolean, uuid[]) to authenticated;

create or replace function public.practice_answer(p_question_id uuid, p_selected char(1))
returns table (is_correct boolean, correct_option char(1), explanation text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare v_q public.questions; v_ok boolean;
begin
  if auth.uid() is null then raise exception 'Not authorized'; end if;
  select * into v_q from public.questions where id = p_question_id and is_active;
  if v_q.id is null then raise exception 'Question not found'; end if;
  if exists (select 1 from public.daily_test_questions dq join public.daily_tests dt on dt.id = dq.daily_test_id
             where dq.question_id = p_question_id and dt.status <> 'published') then
    raise exception 'This question is not available for practice yet.';
  end if;
  v_ok := (p_selected = v_q.correct_option);
  insert into public.practice_answers (student_id, question_id, selected_option, is_correct)
  select auth.uid(), p_question_id, p_selected, v_ok where exists (select 1 from public.students where id = auth.uid());
  return query select v_ok, v_q.correct_option, v_q.explanation;
end;
$$;
grant execute on function public.practice_answer(uuid, character) to authenticated;

-- ---------------------------------------------------------------------
-- 13. Faculty/admin analytics
-- ---------------------------------------------------------------------
create or replace function public.fetch_topic_heatmap(p_daily_test_id uuid default null, p_days int default 30)
returns table (category text, subject text, attempted int, correct int)
language sql security definer stable set search_path = public as $$
  select q.category::text, q.subject, count(*)::int, (count(*) filter (where a.is_correct))::int
  from public.test_answers a
  join public.test_attempts t on t.id = a.attempt_id
  join public.students s on s.id = t.student_id
  join public.questions q on q.id = a.question_id
  where ((public.is_faculty() and s.department_id = public.current_faculty_department())
      or (public.is_admin() and q.category = public.current_admin_category()))
    and ((p_daily_test_id is not null and t.daily_test_id = p_daily_test_id)
      or (p_daily_test_id is null and t.created_at >= now() - make_interval(days => p_days)))
  group by q.category, q.subject
  order by (count(*) filter (where a.is_correct))::float / count(*) asc;
$$;
grant execute on function public.fetch_topic_heatmap(uuid, int) to authenticated;

create or replace function public.fetch_at_risk(p_limit int default 25)
returns table (student_id uuid, register_number text, full_name text, year int,
               avg_pct float8, absences int, trend float8, risk text)
language sql security definer stable set search_path = public as $$
  with recent as (
    select t.student_id as sid, t.status, t.score, t.total_questions,
           row_number() over (partition by t.student_id order by d.test_date desc, d.category) as rn
    from public.test_attempts t join public.daily_tests d on d.id = t.daily_test_id
    where d.status = 'published'
  ),
  agg as (
    select sid,
      count(*) filter (where status = 'absent') as nabs,
      avg(case when status = 'submitted' and total_questions > 0 then score::float / total_questions end) as avgp,
      avg(case when rn <= 3 and status = 'submitted' and total_questions > 0 then score::float / total_questions end) as recp,
      avg(case when rn > 3 and status = 'submitted' and total_questions > 0 then score::float / total_questions end) as prevp
    from recent where rn <= 6 group by sid
  ),
  scored as (
    select s.id as sid, s.register_number as reg, p.full_name as fname, s.year as yr,
           coalesce(a.avgp, 0) as avgp, a.nabs, coalesce(a.recp, a.avgp, 0) - coalesce(a.prevp, a.avgp, 0) as tr,
           case when a.nabs >= 3 or coalesce(a.avgp, 0) < 0.4 then 'High'
                when coalesce(a.avgp, 0) < 0.55 or (coalesce(a.recp, a.avgp, 0) - coalesce(a.prevp, a.avgp, 0)) < -0.15 then 'Medium'
                else 'Low' end as rk
    from agg a join public.students s on s.id = a.sid join public.profiles p on p.id = s.id
    where p.is_active and (public.is_admin() or (public.is_faculty() and s.department_id = public.current_faculty_department()))
  )
  select sid, reg, fname, yr, round((avgp * 100)::numeric, 1)::float8, nabs::int, round((tr * 100)::numeric, 1)::float8, rk
  from scored where rk <> 'Low'
  order by (rk = 'High') desc, avgp asc
  limit least(p_limit, 100);
$$;
grant execute on function public.fetch_at_risk(int) to authenticated;

create or replace function public.fetch_trend(p_days int default 60)
returns table (test_date date, category text, avg_pct float8, submitted int, total int)
language sql security definer stable set search_path = public as $$
  select d.test_date, d.category::text,
         round(avg(case when t.status = 'submitted' and t.total_questions > 0 then 100.0 * t.score / t.total_questions end)::numeric, 1)::float8,
         (count(*) filter (where t.status = 'submitted'))::int, count(*)::int
  from public.daily_tests d
  join public.test_attempts t on t.daily_test_id = d.id
  join public.students s on s.id = t.student_id
  where d.status = 'published' and d.test_date >= current_date - p_days
    and ((public.is_faculty() and s.department_id = public.current_faculty_department())
      or (public.is_admin() and d.category = public.current_admin_category()))
  group by d.test_date, d.category
  order by d.test_date, d.category;
$$;
grant execute on function public.fetch_trend(int) to authenticated;

-- ---------------------------------------------------------------------
-- 14. Near-duplicate question detection (trigram similarity)
-- ---------------------------------------------------------------------
create or replace function public.find_similar_questions(p_text text, p_threshold real default 0.6)
returns table (question_id uuid, question_text text, sim real)
language sql security definer stable set search_path = public, extensions as $$
  select q.id, q.question_text, similarity(q.question_text, p_text)
  from public.questions q
  where public.is_admin() and q.category = public.current_admin_category()
    and similarity(q.question_text, p_text) >= p_threshold
  order by 3 desc limit 5;
$$;
grant execute on function public.find_similar_questions(text, real) to authenticated;

-- ---------------------------------------------------------------------
-- 15. Per-test security/automation options (admin, own category only,
--     only before the test opens)
-- ---------------------------------------------------------------------
create or replace function public.set_test_options(
  p_test_id uuid,
  p_qr_rotating boolean default null,
  p_auto_publish boolean default null,
  p_geo_lat double precision default null,
  p_geo_lng double precision default null,
  p_geo_radius_m int default null,
  p_clear_geofence boolean default false
)
returns public.daily_tests
language plpgsql security definer set search_path = public as $$
declare v_t public.daily_tests;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  select * into v_t from public.daily_tests where id = p_test_id;
  if v_t.id is null then raise exception 'Test not found'; end if;
  if v_t.category is distinct from public.current_admin_category() then
    raise exception 'You can only edit tests in your own category';
  end if;
  if v_t.status not in ('draft', 'scheduled') then
    raise exception 'Options can only be changed before the test opens';
  end if;
  if p_geo_radius_m is not null and (p_geo_radius_m < 20 or p_geo_radius_m > 5000) then
    raise exception 'Geofence radius must be between 20 and 5000 metres';
  end if;

  update public.daily_tests set
    qr_rotating  = coalesce(p_qr_rotating, qr_rotating),
    auto_publish = coalesce(p_auto_publish, auto_publish),
    geo_lat      = case when p_clear_geofence then null else coalesce(p_geo_lat, geo_lat) end,
    geo_lng      = case when p_clear_geofence then null else coalesce(p_geo_lng, geo_lng) end,
    geo_radius_m = case when p_clear_geofence then null else coalesce(p_geo_radius_m, geo_radius_m) end
  where id = p_test_id
  returning * into v_t;
  return v_t;
end;
$$;
grant execute on function public.set_test_options(uuid, boolean, boolean, double precision, double precision, int, boolean) to authenticated;
