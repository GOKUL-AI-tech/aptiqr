-- =====================================================================
-- AptiQR — RPC functions called from the Flutter app via
-- supabase.rpc('function_name', params: {...})
-- Run after schema.sql, auth_trigger.sql, policies.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- start_test_attempt(daily_test_id)
-- Called when a student opens today's test. Creates (or resumes) the
-- attempt row. Blocks a second attempt per student per day.
-- ---------------------------------------------------------------------
create or replace function public.start_test_attempt(p_daily_test_id uuid)
returns public.test_attempts
language plpgsql security definer set search_path = public as $$
declare
  v_attempt public.test_attempts;
  v_test public.daily_tests;
begin
  select * into v_test from public.daily_tests where id = p_daily_test_id;
  if v_test is null then
    raise exception 'Test not found';
  end if;
  if now() < v_test.open_time or now() > v_test.close_time then
    raise exception 'Test is not open right now';
  end if;

  select * into v_attempt from public.test_attempts
    where daily_test_id = p_daily_test_id and student_id = auth.uid();

  if v_attempt is null then
    insert into public.test_attempts (daily_test_id, student_id, status, started_at, total_questions)
    values (p_daily_test_id, auth.uid(), 'in_progress', now(), v_test.question_count)
    returning * into v_attempt;
  elsif v_attempt.status = 'not_started' then
    update public.test_attempts
      set status = 'in_progress', started_at = now()
      where id = v_attempt.id
      returning * into v_attempt;
  elsif v_attempt.status = 'submitted' then
    raise exception 'You have already submitted today''s test';
  end if;

  return v_attempt;
end;
$$;

-- ---------------------------------------------------------------------
-- submit_answer(attempt_id, question_id, selected_option, client_uuid)
-- Upserts a single answer. Used both for live answering and for
-- replaying the offline queue once connectivity returns.
-- ---------------------------------------------------------------------
create or replace function public.submit_answer(
  p_attempt_id uuid,
  p_question_id uuid,
  p_selected_option char(1),
  p_client_uuid text default null
)
returns public.test_answers
language plpgsql security definer set search_path = public as $$
declare
  v_answer public.test_answers;
  v_correct char(1);
  v_owner uuid;
  v_status attempt_status;
  v_daily_test_id uuid;
begin
  select student_id, status, daily_test_id into v_owner, v_status, v_daily_test_id
    from public.test_attempts where id = p_attempt_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not your attempt';
  end if;
  if v_status = 'submitted' then
    raise exception 'Attempt already submitted';
  end if;

  -- Without this, submit_test_attempt's score tally (`count(*) filter
  -- (where is_correct) from test_answers where attempt_id = ...`) would
  -- happily count an answer for ANY question id in the whole bank —
  -- any category, any day — since nothing here previously checked that
  -- p_question_id was actually one of this test's assigned questions.
  if not exists (
    select 1 from public.daily_test_questions
    where daily_test_id = v_daily_test_id and question_id = p_question_id
  ) then
    raise exception 'That question is not part of this test';
  end if;

  select correct_option into v_correct from public.questions where id = p_question_id;

  insert into public.test_answers (attempt_id, question_id, selected_option, is_correct, client_uuid, answered_at)
  values (p_attempt_id, p_question_id, p_selected_option, (p_selected_option = v_correct), p_client_uuid, now())
  on conflict (attempt_id, question_id) do update
    set selected_option = excluded.selected_option,
        is_correct = excluded.is_correct,
        answered_at = excluded.answered_at,
        client_uuid = excluded.client_uuid
  returning * into v_answer;

  return v_answer;
end;
$$;

-- ---------------------------------------------------------------------
-- submit_test_attempt(attempt_id)
-- Finalizes the attempt: locks it, computes the score from test_answers.
-- ---------------------------------------------------------------------
create or replace function public.submit_test_attempt(p_attempt_id uuid)
returns public.test_attempts
language plpgsql security definer set search_path = public as $$
declare
  v_attempt public.test_attempts;
  v_score int;
begin
  select * into v_attempt from public.test_attempts where id = p_attempt_id;
  if v_attempt is null or v_attempt.student_id <> auth.uid() then
    raise exception 'Not your attempt';
  end if;
  if v_attempt.status = 'submitted' then
    return v_attempt;
  end if;

  select count(*) filter (where is_correct) into v_score
    from public.test_answers where attempt_id = p_attempt_id;

  update public.test_attempts
    set status = 'submitted', submitted_at = now(), score = coalesce(v_score, 0)
    where id = p_attempt_id
    returning * into v_attempt;

  return v_attempt;
end;
$$;

-- ---------------------------------------------------------------------
-- cancel_test_attempt(attempt_id)
-- Called when the student backgrounds the app mid-test (anti-cheating —
-- see TestQuestionScreen/TestReviewScreen). Reuses the 'absent' status
-- rather than a new enum value: "started then left before submitting"
-- and "never showed up" are the same outcome for attendance/results.
-- No-ops (doesn't clobber) an already-submitted attempt.
-- ---------------------------------------------------------------------
create or replace function public.cancel_test_attempt(p_attempt_id uuid)
returns public.test_attempts
language plpgsql security definer set search_path = public as $$
declare
  v_attempt public.test_attempts;
begin
  select * into v_attempt from public.test_attempts where id = p_attempt_id;
  if v_attempt is null or v_attempt.student_id <> auth.uid() then
    raise exception 'Not your attempt';
  end if;
  if v_attempt.status = 'submitted' then
    return v_attempt;
  end if;

  update public.test_attempts
    set status = 'absent', submitted_at = now()
    where id = p_attempt_id
    returning * into v_attempt;

  return v_attempt;
end;
$$;

-- ---------------------------------------------------------------------
-- generate_daily_test(test_date, category, question_count, duration_minutes,
--                      open_time, close_time, results_time,
--                      selection_mode, question_ids)
-- Admin-only, and further restricted to the *calling* admin's own
-- category (an Aptitude admin can only generate 'aptitude' tests, etc —
-- see current_admin_category() in policies.sql). Auto mode picks a
-- random spread of active questions *within that category*; manual mode
-- uses the provided question_ids (which must themselves belong to that
-- category — enforced by the questions_select_admin_faculty /
-- questions_write_admin RLS policies the admin's own manual-picker query
-- is already subject to, so a cross-category id simply won't resolve).
-- Also stamps a qr_payload token the faculty QR screen renders.
-- ---------------------------------------------------------------------
create or replace function public.generate_daily_test(
  p_test_date date,
  p_category test_category default 'aptitude',
  p_question_count int default 20,
  p_duration_minutes int default 30,
  p_open_time timestamptz default null,
  p_close_time timestamptz default null,
  p_results_time timestamptz default null,
  p_selection_mode selection_mode default 'auto',
  p_question_ids uuid[] default null
)
returns public.daily_tests
language plpgsql security definer set search_path = public as $$
declare
  v_test public.daily_tests;
  -- `at time zone 'Asia/Kolkata'` matters here: without it, casting a
  -- naive `timestamp` straight to `timestamptz` uses the DB session's
  -- timezone (UTC on Supabase), so "10 hours after midnight" would land
  -- at 10:00 UTC = 3:30 PM IST, not the intended 10:00 AM college time.
  -- This fallback only fires when the caller doesn't pass explicit times
  -- (the admin app always does — see AdminService.generateDailyTest —
  -- but this keeps a direct RPC call, e.g. from the SQL editor, correct
  -- too instead of silently reproducing the same 5.5-hour bug).
  v_open timestamptz := coalesce(p_open_time, (p_test_date::timestamp + interval '10 hours') at time zone 'Asia/Kolkata');
  v_close timestamptz := coalesce(p_close_time, (p_test_date::timestamp + interval '14 hours') at time zone 'Asia/Kolkata');
  v_results timestamptz := coalesce(p_results_time, (p_test_date::timestamp + interval '15 hours') at time zone 'Asia/Kolkata');
  v_qid uuid;
  v_order int := 1;
  v_available int;
begin
  if not public.is_admin() then
    raise exception 'Admin only';
  end if;
  -- `is distinct from` (not `<>`) matters here: if this admin's `admins`
  -- row is ever missing (e.g. via the admins_delete_self RLS policy —
  -- see policies.sql), current_admin_category() returns NULL, and plain
  -- SQL `NULL <> p_category` evaluates to NULL rather than true/false —
  -- `if NULL then` is treated as false, so the exception below used to
  -- be silently skipped and a category-less admin could generate a test
  -- for ANY category, defeating the whole per-category admin silo model.
  -- `is distinct from` treats NULL as a real, comparable value, so this
  -- now correctly raises whenever the two aren't the same non-null value.
  if public.current_admin_category() is distinct from p_category then
    raise exception 'You can only generate tests for your own category (%)', public.current_admin_category();
  end if;

  -- Guard against silently creating an empty test. The auto-select loop
  -- below is a plain `limit p_question_count` — if the category's
  -- question bank has fewer active questions than requested (including
  -- zero), it used to just insert however many it found with no error,
  -- leaving a daily_tests row that *reports* p_question_count questions
  -- (that column stores what was requested, not what was actually
  -- attached) but has 0 rows in daily_test_questions. The app showed
  -- "Test generated" and the QR would open to a blank test for
  -- students. Checking the pool size up front before the row is even
  -- created turns that into a clear error instead.
  if p_selection_mode = 'auto' then
    select count(*) into v_available from public.questions where is_active = true and category = p_category;
    if v_available = 0 then
      raise exception 'No active % questions in the bank yet — add questions before generating a test.', p_category;
    elsif v_available < p_question_count then
      raise exception 'Only % active % question(s) available, but % were requested — add more questions or lower the question count.',
        v_available, p_category, p_question_count;
    end if;
  elsif p_selection_mode = 'manual' and (p_question_ids is null or array_length(p_question_ids, 1) is null) then
    raise exception 'Select at least one question for a manual test.';
  end if;

  insert into public.daily_tests (
    test_date, category, question_count, duration_minutes, open_time, close_time,
    results_time, selection_mode, status, qr_payload, created_by
  ) values (
    p_test_date, p_category, p_question_count, p_duration_minutes, v_open, v_close,
    v_results, p_selection_mode, 'scheduled',
    -- Was encode(gen_random_bytes(16), 'hex') — gen_random_bytes() comes
    -- from the pgcrypto extension, which on Supabase-hosted Postgres
    -- installs into the `extensions` schema by default, not `public`.
    -- This function's `set search_path = public` (needed for security
    -- definer functions generally) can't see it there, so every call
    -- failed with "function gen_random_bytes(integer) does not exist"
    -- even though `create extension pgcrypto` in schema.sql had already
    -- run successfully. gen_random_uuid() is built into core Postgres
    -- (13+, pg_catalog — always in scope, no extension needed) and gives
    -- the same 32-hex-character token shape once the dashes are removed.
    replace(gen_random_uuid()::text, '-', ''), auth.uid()
  )
  returning * into v_test;

  if p_selection_mode = 'manual' and p_question_ids is not null then
    foreach v_qid in array p_question_ids loop
      insert into public.daily_test_questions (daily_test_id, question_id, question_order)
      values (v_test.id, v_qid, v_order);
      v_order := v_order + 1;
    end loop;
  else
    for v_qid in
      select id from public.questions
      where is_active = true and category = p_category
      order by random()
      limit p_question_count
    loop
      insert into public.daily_test_questions (daily_test_id, question_id, question_order)
      values (v_test.id, v_qid, v_order);
      v_order := v_order + 1;
    end loop;
  end if;

  return v_test;
end;
$$;

-- ---------------------------------------------------------------------
-- update_daily_test(test_id, ...)
-- Admin-only. Edits a test that hasn't opened yet ('draft' or
-- 'scheduled' only — once students can start attempting it, changing
-- the question count/set or timing would invalidate attempts already in
-- progress, so this deliberately refuses on 'open'/'closed'/'published').
-- Every parameter besides p_test_id is optional (null = leave as-is),
-- so the app can send only the fields the admin actually changed.
-- Re-picks the question set when question_count, selection_mode, or
-- question_ids was actually supplied — cheap edits like duration alone
-- shouldn't reshuffle an already-fine set of questions.
-- ---------------------------------------------------------------------
create or replace function public.update_daily_test(
  p_test_id uuid,
  p_test_date date default null,
  p_question_count int default null,
  p_duration_minutes int default null,
  p_open_time timestamptz default null,
  p_close_time timestamptz default null,
  p_results_time timestamptz default null,
  p_selection_mode selection_mode default null,
  p_question_ids uuid[] default null
)
returns public.daily_tests
language plpgsql security definer set search_path = public as $$
declare
  v_test public.daily_tests;
  v_new_count int;
  v_new_mode selection_mode;
  v_qid uuid;
  v_order int := 1;
  v_available int;
begin
  if not public.is_admin() then
    raise exception 'Admin only';
  end if;

  select * into v_test from public.daily_tests where id = p_test_id;
  if v_test.id is null then
    raise exception 'Test not found';
  end if;
  -- An admin can only ever have found their own category's test in the
  -- first place via the app's UI (fetch_recent_tests filters by their
  -- category), but this RPC bypasses table-owner RLS like every
  -- SECURITY DEFINER function here — enforce the same boundary
  -- explicitly rather than relying on the client to never send someone
  -- else's test id.
  -- See the `is distinct from` note in generate_daily_test above — `<>`
  -- against a NULL current_admin_category() silently skips this check.
  if v_test.category is distinct from public.current_admin_category() then
    raise exception 'You can only edit tests in your own category';
  end if;
  if v_test.status not in ('draft', 'scheduled') then
    raise exception 'Only a scheduled test that hasn''t opened yet can be edited';
  end if;

  v_new_count := coalesce(p_question_count, v_test.question_count);
  v_new_mode := coalesce(p_selection_mode, v_test.selection_mode);

  -- Same guard as generate_daily_test: check the pool before touching
  -- anything, so a reshuffle that would leave the test with 0 questions
  -- fails loudly instead of silently deleting the old question set and
  -- replacing it with nothing.
  if v_new_mode = 'auto' and (p_question_count is not null or p_selection_mode is not null) then
    select count(*) into v_available from public.questions where is_active = true and category = v_test.category;
    if v_available = 0 then
      raise exception 'No active % questions in the bank yet — add questions before reshuffling.', v_test.category;
    elsif v_available < v_new_count then
      raise exception 'Only % active % question(s) available, but % were requested — add more questions or lower the question count.',
        v_available, v_test.category, v_new_count;
    end if;
  elsif v_new_mode = 'manual' and p_question_ids is not null and array_length(p_question_ids, 1) is null then
    raise exception 'Select at least one question for a manual test.';
  end if;

  update public.daily_tests set
    test_date = coalesce(p_test_date, test_date),
    question_count = v_new_count,
    duration_minutes = coalesce(p_duration_minutes, duration_minutes),
    open_time = coalesce(p_open_time, open_time),
    close_time = coalesce(p_close_time, close_time),
    results_time = coalesce(p_results_time, results_time),
    selection_mode = v_new_mode
  where id = p_test_id
  returning * into v_test;

  if p_question_count is not null or p_selection_mode is not null or p_question_ids is not null then
    delete from public.daily_test_questions where daily_test_id = p_test_id;

    if v_new_mode = 'manual' and p_question_ids is not null then
      foreach v_qid in array p_question_ids loop
        insert into public.daily_test_questions (daily_test_id, question_id, question_order)
        values (p_test_id, v_qid, v_order);
        v_order := v_order + 1;
      end loop;
    else
      -- Must filter by v_test.category here — this function is SECURITY
      -- DEFINER (runs as table owner, bypassing the questions_select_
      -- admin_faculty RLS policy entirely, unlike a normal client-side
      -- query), so without this filter an auto-mode reshuffle could pull
      -- in another category's questions onto this test's paper. See the
      -- matching `and category = p_category` in generate_daily_test above
      -- — this was missing here and is the same bug in a second spot.
      for v_qid in
        select id from public.questions
        where is_active = true and category = v_test.category
        order by random()
        limit v_new_count
      loop
        insert into public.daily_test_questions (daily_test_id, question_id, question_order)
        values (p_test_id, v_qid, v_order);
        v_order := v_order + 1;
      end loop;
    end if;
  end if;

  return v_test;
end;
$$;

-- ---------------------------------------------------------------------
-- delete_daily_test(test_id)
-- Admin-only. Unlike update_daily_test, this is deliberately allowed at
-- ANY status, including 'published' — the scenario that motivated this
-- was an admin stuck unable to generate a new test for a date because
-- one already existed (test_date is unique) and the existing one had
-- already moved past 'scheduled', so update_daily_test correctly refuses
-- to edit it. Deleting cascades to daily_test_questions, test_attempts,
-- test_answers, and rankings (all `on delete cascade` — see
-- schema.sql), so this permanently destroys every student's attempt/
-- answers/ranking for that day. The app must confirm with the admin
-- before calling this, especially for anything past 'scheduled'.
-- ---------------------------------------------------------------------
create or replace function public.delete_daily_test(p_test_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_category test_category;
begin
  if not public.is_admin() then
    raise exception 'Admin only';
  end if;

  select category into v_category from public.daily_tests where id = p_test_id;
  if v_category is null then
    return; -- already gone — nothing to do, matches prior no-op-on-missing-id behavior
  end if;
  -- See the `is distinct from` note in generate_daily_test above.
  if v_category is distinct from public.current_admin_category() then
    raise exception 'You can only delete tests in your own category';
  end if;

  delete from public.daily_tests where id = p_test_id;
end;
$$;

-- ---------------------------------------------------------------------
-- publish_results(daily_test_id)
-- Admin-only (or a scheduled Edge Function at results_time). Marks any
-- unsubmitted attempt as absent, computes overall / department / year
-- ranks and writes the rankings table.
-- ---------------------------------------------------------------------
create or replace function public.publish_results(p_daily_test_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_category test_category;
begin
  if not public.is_admin() then
    raise exception 'Admin only';
  end if;

  -- Same category-silo check as generate_daily_test/update_daily_test/
  -- delete_daily_test — this one was missing it, which let any admin
  -- publish (mark absences, compute rankings, flip status) another
  -- category's test.
  select category into v_category from public.daily_tests where id = p_daily_test_id;
  if v_category is null then
    raise exception 'Test not found';
  end if;
  -- See the `is distinct from` note in generate_daily_test above.
  if v_category is distinct from public.current_admin_category() then
    raise exception 'You can only publish results for tests in your own category';
  end if;

  update public.test_attempts
    set status = 'absent'
    where daily_test_id = p_daily_test_id
      and status in ('not_started', 'in_progress');

  -- Students who never opened the test at all have no test_attempts row
  -- yet (start_test_attempt only creates one when a student actually
  -- scans the QR) — without this backfill they'd never be counted as
  -- absent anywhere (monitoring, reports) once results publish.
  insert into public.test_attempts (daily_test_id, student_id, status, total_questions)
  select p_daily_test_id, s.id, 'absent', dt.question_count
  from public.students s
  join public.profiles p on p.id = s.id
  cross join public.daily_tests dt
  where dt.id = p_daily_test_id
    and p.is_active = true
    and not exists (
      select 1 from public.test_attempts a
      where a.daily_test_id = p_daily_test_id and a.student_id = s.id
    );

  delete from public.rankings where daily_test_id = p_daily_test_id;

  insert into public.rankings (daily_test_id, student_id, department_id, year, score, rank_overall, rank_department, rank_year)
  select
    a.daily_test_id,
    a.student_id,
    s.department_id,
    s.year,
    coalesce(a.score, 0) as score,
    rank() over (order by coalesce(a.score, 0) desc) as rank_overall,
    rank() over (partition by s.department_id order by coalesce(a.score, 0) desc) as rank_department,
    rank() over (partition by s.year order by coalesce(a.score, 0) desc) as rank_year
  from public.test_attempts a
  join public.students s on s.id = a.student_id
  where a.daily_test_id = p_daily_test_id
    and a.status = 'submitted';

  update public.daily_tests set status = 'published' where id = p_daily_test_id;
end;
$$;

-- ---------------------------------------------------------------------
-- fetch_test_questions(daily_test_id)
-- Returns today's question paper for the calling student, WITHOUT
-- correct_option, so the app can cache it on-device (see
-- StudentService._cacheQuestions).
--
-- Why this exists instead of a plain client-side select: `questions`
-- intentionally has no student SELECT policy at all (see policies.sql —
-- "students never see the bank directly, only today's paper"), so a
-- client-side embedded query like
-- `daily_test_questions.select('..., questions(...)')` silently gets
-- `questions: null` back for every row once RLS filters it out for a
-- student caller (PostgREST doesn't error on a blocked embed, it just
-- nulls it), which crashed the app with a bare type-cast exception
-- instead of a real error message.
--
-- Adding a student-facing SELECT policy on `questions` instead would
-- "fix" that, but RLS only controls *row* visibility, not *column*
-- visibility — such a policy would also hand back correct_option (the
-- answer key) to anyone hitting the Supabase REST API directly with
-- their own session, bypassing the app entirely. This function stays
-- SECURITY DEFINER (so it can read `questions` regardless of the
-- caller's RLS) but only ever returns the columns a student is allowed
-- to see, and separately verifies the caller actually has a live
-- attempt on this test before returning anything at all.
-- ---------------------------------------------------------------------
create or replace function public.fetch_test_questions(p_daily_test_id uuid)
returns table (
  question_order int,
  question_id uuid,
  subject text,
  question_text text,
  option_a text,
  option_b text,
  option_c text,
  option_d text
)
language plpgsql security definer stable set search_path = public as $$
declare
  v_category test_category;
begin
  -- An admin is only ever siloed to their own category everywhere else
  -- (questions_write_admin, generate_daily_test, publish_results, ...);
  -- this function's `is_admin()` short-circuit let ANY admin fetch ANY
  -- category's live question paper (answer key excluded, but still the
  -- full text/options of another category's test) — inconsistent with
  -- that model and tightened to match it. Faculty stay unrestricted
  -- (they legitimately see all 3 categories' papers).
  if public.is_admin() then
    select category into v_category from public.daily_tests where id = p_daily_test_id;
    -- See the `is distinct from` note in generate_daily_test above — the
    -- old `<>` here had the same NULL-fails-open gap.
    if v_category is null or v_category is distinct from public.current_admin_category() then
      raise exception 'Not authorized';
    end if;
  elsif not public.is_faculty() and not exists (
    select 1 from public.test_attempts
    where daily_test_id = p_daily_test_id
      and student_id = auth.uid()
      and status in ('in_progress', 'submitted')
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  select dtq.question_order, q.id, q.subject, q.question_text,
         q.option_a, q.option_b, q.option_c, q.option_d
  from public.daily_test_questions dtq
  join public.questions q on q.id = dtq.question_id
  where dtq.daily_test_id = p_daily_test_id
  order by dtq.question_order;
end;
$$;

grant execute on function public.fetch_test_questions(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- fetch_top_rankings(daily_test_id, scope, department_id, year, limit)
-- Faculty Ranking screen (Overall / Department / Year tabs).
--
-- Why this exists instead of the plain client-side
-- `rankings.select('*, students(register_number, profiles(full_name)))'`
-- FacultyService.fetchTop10 used before: `students_select` (policies.sql)
-- only lets a faculty caller read rows where department_id equals their
-- own department. The Overall and Year tabs intentionally span every
-- department, and the Department tab (since the dropdown added to let
-- faculty browse any department, not just their own) can now target a
-- department that isn't the caller's. For every row outside the
-- caller's own department, the embedded `students(...)` join above was
-- silently coming back null (PostgREST doesn't error on an RLS-blocked
-- embed, it just nulls it) — RankingEntry.fromJson tolerates that null
-- without crashing, so this shipped as a quiet bug: blank name/register
-- number for any student outside the viewing faculty's own department,
-- on exactly the tabs meant to show other departments. Same root cause,
-- and same fix shape, as fetch_test_questions above.
-- ---------------------------------------------------------------------
create or replace function public.fetch_top_rankings(
  p_daily_test_id uuid,
  p_scope text default 'overall',
  p_department_id uuid default null,
  p_year int default null,
  p_limit int default 10
)
returns table (
  student_id uuid,
  register_number text,
  full_name text,
  department_id uuid,
  year int,
  score int,
  rank_overall int,
  rank_department int,
  rank_year int
)
language plpgsql security definer stable set search_path = public as $$
begin
  if not (public.is_admin() or public.is_faculty()) then
    raise exception 'Not authorized';
  end if;

  return query
  select r.student_id, s.register_number, p.full_name, r.department_id, r.year,
         r.score, r.rank_overall, r.rank_department, r.rank_year
  from public.rankings r
  join public.students s on s.id = r.student_id
  join public.profiles p on p.id = s.id
  where r.daily_test_id = p_daily_test_id
    and (p_scope <> 'department' or r.department_id = p_department_id)
    and (p_scope <> 'year' or r.year = p_year)
  order by case p_scope
    when 'department' then r.rank_department
    when 'year' then r.rank_year
    else r.rank_overall
  end
  limit p_limit;
end;
$$;

grant execute on function public.fetch_top_rankings(uuid, text, uuid, int, int) to authenticated;

-- ---------------------------------------------------------------------
-- fetch_attendance(daily_test_id, year, section)
-- Faculty Student Monitoring / Reports. Left-joins every student in the
-- caller's department (RLS-equivalent check done here since this runs as
-- security definer) against test_attempts for this test, so students who
-- never even opened the test still show up (as 'not_started', or
-- 'absent' once publish_results has backfilled/marked them). Querying
-- test_attempts directly (the old approach) only ever returned students
-- who already had a row there — anyone who hadn't started was invisible
-- and never counted anywhere.
-- ---------------------------------------------------------------------
create or replace function public.fetch_attendance(
  p_daily_test_id uuid,
  p_year int default null,
  p_section text default null
)
returns table (
  student_id uuid,
  register_number text,
  full_name text,
  department_id uuid,
  year int,
  section text,
  attempt_id uuid,
  status text,
  score int,
  total_questions int,
  started_at timestamptz,
  submitted_at timestamptz
)
language plpgsql security definer stable set search_path = public as $$
begin
  if not (public.is_admin() or public.is_faculty()) then
    raise exception 'Not authorized';
  end if;

  return query
  select
    s.id,
    s.register_number,
    p.full_name,
    s.department_id,
    s.year,
    s.section,
    a.id,
    coalesce(a.status::text, 'not_started'),
    a.score,
    a.total_questions,
    a.started_at,
    a.submitted_at
  from public.students s
  join public.profiles p on p.id = s.id
  left join public.test_attempts a
    on a.student_id = s.id and a.daily_test_id = p_daily_test_id
  where (public.is_admin() or s.department_id = public.current_faculty_department())
    and (p_year is null or s.year = p_year)
    and (p_section is null or s.section = p_section)
  order by s.register_number;
end;
$$;

grant execute on function public.fetch_attendance(uuid, int, text) to authenticated;
