-- =====================================================================
-- AptiQR — Dummy data for manual end-to-end testing.
--
-- Run this in the Supabase SQL Editor any time after schema.sql,
-- auth_trigger.sql, auth_helpers.sql, policies.sql and functions.sql
-- have all been run at least once, and after you have at least one
-- admin account (README step 1.4).
--
-- IMPORTANT: this does NOT call the generate_daily_test() RPC — that RPC
-- checks is_admin() via auth.uid(), which is null when you run SQL
-- directly from the SQL Editor (you're not signed in as an app user
-- there), so it would just raise "Admin only". Instead this inserts the
-- daily_tests / daily_test_questions rows directly, which is exactly
-- what that RPC does under the hood.
--
-- Safe to re-run: the questions insert always adds a fresh batch (they're
-- just sample data, harmless to have duplicates), and the daily-test
-- block skips itself if today's test already exists.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 10 sample questions across 3 subjects, so a generated test has some
-- variety. Answers are intentionally varied (not always "C") so you can
-- actually see right/wrong scoring work.
-- ---------------------------------------------------------------------
insert into public.questions
  (subject, topic, question_text, option_a, option_b, option_c, option_d, correct_option, difficulty, is_active)
values
  ('Quantitative Aptitude', 'Percentages', 'What is 20% of 150?', '20', '30', '35', '40', 'B', 'easy', true),
  ('Quantitative Aptitude', 'Averages', 'The average of 4, 8, 12 and 16 is:', '8', '9', '10', '12', 'C', 'easy', true),
  ('Quantitative Aptitude', 'Ratios', 'Simplify the ratio 12:18.', '1:2', '2:3', '3:4', '4:5', 'B', 'medium', true),
  ('Quantitative Aptitude', 'Time & Work', 'A can finish a job in 10 days, B in 15 days. Working together, how many days?', '5', '6', '8', '12', 'B', 'medium', true),
  ('Logical Reasoning', 'Number Series', 'Find the next number: 2, 4, 8, 16, ?', '18', '24', '32', '36', 'C', 'easy', true),
  ('Logical Reasoning', 'Analogy', 'Book is to Reading as Fork is to:', 'Writing', 'Drawing', 'Eating', 'Cutting', 'C', 'easy', true),
  ('Logical Reasoning', 'Coding-Decoding', 'If CAT is coded as DBU, how is DOG coded?', 'EPH', 'EPI', 'FQH', 'DPI', 'A', 'medium', true),
  ('Verbal Ability', 'Synonyms', 'Choose the synonym of "Abundant":', 'Scarce', 'Plentiful', 'Empty', 'Limited', 'B', 'easy', true),
  ('Verbal Ability', 'Antonyms', 'Choose the antonym of "Optimistic":', 'Hopeful', 'Cheerful', 'Pessimistic', 'Positive', 'C', 'easy', true),
  ('Verbal Ability', 'Sentence Correction', 'Which sentence is grammatically correct?', 'He don''t like tea.', 'He doesn''t likes tea.', 'He doesn''t like tea.', 'He not like tea.', 'C', 'medium', true);

-- ---------------------------------------------------------------------
-- Today's test — open right now, closes in 4 hours, so you can log in
-- as a student immediately and take it without waiting for the default
-- 10 AM - 2 PM window. qr_payload is a plain, typeable string (not
-- random hex) specifically so you can generate a scannable QR for it
-- from any free QR-generator site/app if you're testing on an emulator
-- without a usable camera — just encode the literal text
-- 'APTIQR-DUMMY-TEST-QR' into a QR image and point the app's scanner at
-- it (or a second physical device showing the Faculty > Today's QR
-- screen, which will render this exact same payload).
-- ---------------------------------------------------------------------
do $$
declare
  v_test_id uuid;
  v_qid uuid;
  v_order int := 1;
begin
  -- Filtered by category too, not just test_date — since daily_tests'
  -- uniqueness is now (test_date, category), an existing Technical/
  -- Communication test for today no longer means an Aptitude one
  -- exists, and the old date-only check would have silently skipped
  -- creating this seed test in that case with no warning that anything
  -- was different from what the notice below claims.
  if exists (select 1 from public.daily_tests where test_date = current_date and category = 'aptitude') then
    raise notice 'An aptitude test for today (%) already exists — leaving it alone.', current_date;
  else
    insert into public.daily_tests (
      test_date, category, question_count, duration_minutes,
      open_time, close_time, results_time,
      selection_mode, status, qr_payload, qr_rotating
    ) values (
      current_date, 'aptitude', 10, 15,
      now(),
      now() + interval '4 hours',
      now() + interval '4 hours 5 minutes',
      'auto', 'open',
      'APTIQR-DUMMY-TEST-QR', false
    ) returning id into v_test_id;

    for v_qid in
      select id from public.questions where is_active = true and category = 'aptitude' order by random() limit 10
    loop
      insert into public.daily_test_questions (daily_test_id, question_id, question_order)
      values (v_test_id, v_qid, v_order);
      v_order := v_order + 1;
    end loop;

    raise notice 'Created today''s test (id: %) with 10 questions, open now for 4 hours.', v_test_id;
  end if;
end $$;

-- Sanity check — should show exactly one aptitude row for today.
select id, test_date, category, question_count, duration_minutes, open_time, close_time, status, qr_payload
from public.daily_tests
where test_date = current_date and category = 'aptitude';
