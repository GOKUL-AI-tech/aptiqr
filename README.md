# AptiQR — Daily Aptitude Test

Nehru Arts & Science College, Coimbatore — a daily QR-gated aptitude test app.
Flutter frontend, Supabase backend. Three roles: **Student**, **Faculty**, **Admin**.

For Android APKs, Windows desktop builds, iOS prerequisites, and current
platform limitations, see [BUILDING.md](BUILDING.md).

> **Already have a Supabase project running?** Re-run `supabase/functions.sql`
> in the SQL Editor after pulling the latest code — it now adds a
> `fetch_attendance` RPC (faculty monitoring/reports previously only showed
> students who'd already started the test) and backfills absent attempts in
> `publish_results` for students who never opened the test at all. Both are
> `create or replace`, so re-running the whole file is safe.
>
> **"Forgot password?" now actually works end to end** — it previously sent
> an email (if you typed one) but nothing existed to catch the link when
> tapped, so it went nowhere. This needs: (1) a full rebuild (the Android
> manifest changed — `flutter pub get` then a full stop/re-run, not hot
> reload), and (2) the one-time Supabase Dashboard step in section 1.6
> below.
>
> **Departments screen crashing with `RangeError (end): Invalid value:
> Only valid value is 0: 2`?** A department was created with a blank code
> before the Add sheet had real validation — the code badge assumed every
> code was at least 2 characters and crashed rendering that row. Fixed
> (defensively, for any short code), and you can now delete that bad row
> directly: it shows as "(no code)" in red. The screen also now shows
> inactive departments (previously toggling one off made it silently
> disappear from this screen with no way back).
>
> **Stuck with "A test for [date] already exists" and the existing one
> is already published/closed (so it can't be edited)?** Re-run
> `supabase/functions.sql` for the new `delete_daily_test` RPC, then use
> the trash icon next to that test in Recent tests — deletion is allowed
> at any status (editing isn't, deliberately). This permanently removes
> that day's attempts/answers/rankings, so it asks for confirmation
> first.
>
> **This update: faculty can now import students, admin can bulk-import
> both students and faculty, and most list screens now support pull-to-
> refresh.**
> - Faculty → Profile → "Import students" bulk-adds students into their
>   own department only (no department column needed in the file — the
>   `create-user` Edge Function enforces this server-side, ignoring
>   anything the app sends). **Redeploy the Edge Function to pick this
>   up:** `supabase functions deploy create-user`.
> - Admin → Students & Faculty now has an upload icon in the app bar for
>   bulk-importing either tab from a .csv/.xlsx file, same skip-reason
>   reporting as the Question Bank import.
> - Swipe down to refresh on: Departments, Question Bank, Students &
>   Faculty, Results, Reports & Analytics (admin); Student Monitoring,
>   Ranking, Reports (faculty); Progress, Result (student). Previously
>   the only way to get fresh data on most of these was leaving the
>   screen and coming back, which tears down and rebuilds the whole
>   screen from a blank loading spinner — genuinely slower than an
>   in-place refresh, which is what was likely behind "the refresh is
>   slow."
>
> **This update: department creation, test date/time editing, and a
> visual redesign of the four "home" screens.**
> - "Add department" previously had zero error handling — an empty field
>   or duplicate code left the button spinning forever with no feedback.
>   Now validated with a real error message.
> - The Daily Test edit sheet can now change the test date and open/
>   close/results time, not just question count/duration/mode — and the
>   generate form now shows/lets you set open/close/results time instead
>   of silently using fixed defaults.
> - Splash, Role Select, Student Home, Admin Dashboard, and Faculty
>   Today's QR were redesigned with gradient hero headers, icon badges,
>   and real shadow depth instead of flat bordered boxes — going beyond
>   the earlier shared-theme-only polish pass. Other screens still use
>   the shared theme tokens (colors/fonts/rounded components) but haven't
>   had this deeper per-screen treatment yet.
>
> **QR scanner showing "Could not start the camera (genericError)"?**
> Two things changed: (1) `AndroidManifest.xml` now declares the camera
> permission it was missing entirely (this was the original cause of a
> blank black screen with no message at all), and (2) `mobile_scanner`
> is bumped from 5.2.3 to ^7.2.0 for a long list of camera-start/
> controller-lifecycle bugfixes shipped since 5.2.3 — genericError on
> start is exactly the class of bug those releases fixed. Run
> `flutter pub get` (new dependency version) then a full rebuild (manifest
> changed too). If it still fails after that, run `flutter run` over USB
> instead of installing a release APK — mobile_scanner deliberately hides
> the real underlying error message in release builds and only shows it
> in debug mode, so that's the only way to see what's actually failing.
>
> **Recent tests on the Daily Test screen are now editable.** Tap a row
> whose status is still "scheduled" (not yet "open") to change its
> question count, duration, or selection mode via a new `update_daily_test`
> RPC — re-run `supabase/functions.sql` to pick this up.
>
> **Getting `function gen_random_bytes(integer) does not exist` when
> generating a daily test?** Re-run `supabase/functions.sql` again — the
> QR token generator no longer depends on the `pgcrypto` extension (which
> Supabase installs into the `extensions` schema by default, invisible to
> this `security definer` function's restricted `search_path = public`,
> even though `create extension pgcrypto` itself succeeds). It now uses
> Postgres's built-in `gen_random_uuid()` instead — no extension needed.
>
> **Seeing a "Your app uses the following plugins that apply Kotlin Gradle
> Plugin (KGP): mobile_scanner, share_plus" warning during `flutter build
> apk` / `flutter run`?** This is expected and harmless — it's not a build
> failure. `android/gradle.properties` already has `android.builtInKotlin=false`
> and `android.newDsl=false`, which is Flutter's own official temporary
> workaround for plugins that haven't migrated to "Built-in Kotlin" yet (see
> the comment above those two lines). Neither plugin has shipped that
> migration as of mid-2026 — nothing to fix here until they do.

## 1. Supabase project setup

1. Create a project at [supabase.com](https://supabase.com).
2. In the SQL Editor, run these files **in order**:
   1. `supabase/schema.sql`
   2. `supabase/auth_trigger.sql`
   3. `supabase/auth_helpers.sql`
   4. `supabase/policies.sql`
   5. `supabase/functions.sql`
3. Deploy the admin user-provisioning Edge Function (creates student/faculty
   Supabase Auth accounts — needs the service role key, so it must run
   server-side):
   ```bash
   supabase functions deploy create-user
   ```
4. Create your first admin account manually (Auth → Users → Add user, or
   `supabase.auth.admin.createUser`), then insert its row with the category
   it manages — one of `'aptitude'`, `'technical'`, `'communication'`:
   ```sql
   insert into public.admins (id, category) values ('<the-new-user-uuid>', 'aptitude');
   ```
   (the `handle_new_user` trigger already created its `profiles` row with
   `role = 'admin'` if you passed `{"role": "admin"}` in the user's metadata —
   otherwise update `public.profiles.role` for that row to `'admin'`.)

   **Creating the Technical / Communication admin logins:** each admin login
   is scoped to exactly one category — an Aptitude admin only ever sees/
   manages Aptitude questions and the Aptitude daily test/QR, and likewise
   for Technical and Communication (see `current_admin_category()` in
   `policies.sql`). Repeat step 4 twice more, once per remaining category,
   either the same manual way (create the Auth user, then
   `insert into public.admins (id, category) values (..., 'technical')` /
   `'communication'`), or — once your *first* admin account is signed in —
   from inside the app by calling the `create-user` Edge Function with
   `{"role": "admin", "category": "technical", ...}` (there's no in-app
   "Add admin" screen yet, so this means calling the function directly,
   e.g. via `supabase.functions.invoke` in a one-off script, or `curl` with
   that admin's access token).
5. Copy your project's URL and anon key (Project Settings → API) — you'll
   need them in step 3 below.
6. For "Forgot password?" to actually work: go to Authentication → URL
   Configuration → Redirect URLs and add `aptiqr://reset-callback`. Without
   this exact entry, Supabase silently refuses to redirect there and the
   emailed reset link won't bring the user back into the app. (This app
   also sends via Supabase's built-in email service by default, which is
   rate-limited to a handful of emails/hour — for real use, set up a
   custom SMTP provider under Authentication → Email Templates → SMTP
   Settings.)

## 2. Flutter project setup

Platform folders already exist for Android, iOS, Windows, and web. Keep their
custom platform configuration when setting up this checkout.

```bash
cd "AptiQR"
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates lib/local_db/app_database.g.dart (drift)
```

## 3. Supabase credentials

Create `env/dev.json` (gitignored) with:

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR-ANON-KEY"
}
```

Run with:

```bash
flutter run --dart-define-from-file=env/dev.json
```

> **Update:** `lib/core/config/env.dart` now has this project's actual dev
> Supabase URL/anon key baked in as the *default*, so plain
> `flutter build apk` or `flutter run` (no `--dart-define` flag at all)
> works correctly too — the flag is only needed if you ever want to point
> a build at a *different* Supabase project (e.g. a separate
> staging/production instance). This is safe because Supabase's anon key
> is designed to ship inside client apps — it's gated by Row Level
> Security (`supabase/policies.sql`), not secrecy. If the app ever shows
> a "Supabase isn't configured" screen, it means `env.dart` was edited
> back to the placeholder values, not that the flag was forgotten.

(or pass `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
directly — see `lib/core/config/env.dart`.)

## 4. Seed data to try it end-to-end

1. Sign in as admin → **Departments** → confirm AIML/CSE/IT/ECE/BCA/MCA are
   there (seeded by `schema.sql`).
2. **Question Bank** → add a few questions manually, or bulk-import via
   **Upload** (xlsx/csv — columns: Subject, Topic, Question, Option A-D,
   Correct, Difficulty).
3. **Students & Faculty** → add at least one student and one faculty member
   (this calls the `create-user` Edge Function, so it must be deployed first).
4. **Daily Test** → generate today's test (auto mode needs ≥ question count
   active questions in the bank).
5. Sign in as faculty → **Today's QR** shows the generated code.
6. Sign in as student → Home → Start Test → scan that QR (on a physical
   device/simulator with camera access) → answer → submit.
7. Back as admin → **Results** → Publish once you're ready to reveal
   rankings; student's **Results** tab and faculty's **Ranking** tab update.

## Project structure

```
lib/
  core/            theme, router, Supabase client, env config, utils
  local_db/        drift (SQLite) schema for offline test-taking
  models/          plain Dart data classes mirroring Supabase tables
  services/        one class per domain (auth, student, faculty, admin, sync)
  providers/       Riverpod providers wiring services into the UI
  features/
    splash/, auth/            role select + 3 login flows
    student/                  home, test flow (instructions → question → review), result, progress, profile
    faculty/                  today's QR, monitoring, ranking, reports, profile
    admin/                    dashboard, question bank, people, departments, daily test, results, analytics, profile
  widgets/         shared building blocks (buttons, empty states, QR scanner)
supabase/
  schema.sql, auth_trigger.sql, auth_helpers.sql, policies.sql, functions.sql
  functions/create-user/index.ts
```

## Design decisions worth knowing about

- **Auth**: Supabase Auth (email + password) underlies all three roles.
  Students sign in with their **register number** and faculty with their
  **faculty ID** — both are resolved to the underlying auth email via a
  public RPC (`lookup_student_login_email` / `lookup_faculty_login_email`)
  before the normal password sign-in call.
- **Offline test-taking**: answers are written to an on-device SQLite
  database (via `drift`) the moment a student taps an option, then
  opportunistically pushed to Supabase (`submit_answer` RPC). If the device
  is offline when the student submits, the attempt is flagged
  `pendingSubmit` locally and auto-submitted the next time connectivity
  returns (`OfflineSyncService`, triggered by `connectivity_plus`).
- **QR gating**: each day's test gets a random `qr_payload` token
  (`generate_daily_test` RPC). Faculty display it (`qr_flutter`); students
  scan it (`mobile_scanner`) before their attempt is allowed to start —
  this keeps the test tied to students who are physically in class.
- **Row Level Security**: students only ever see their own data; faculty
  are scoped to their assigned department via `current_faculty_department()`;
  admins bypass all restrictions via `is_admin()`. See `supabase/policies.sql`.

## Known gaps / next steps

- See BUILDING.md for platform limitations and required toolchains.
- Desktop scanner fallback has widget tests; full backend/device testing is still needed.
- Admin "manual publish" is instant; a scheduled Edge Function calling
  `publish_results` at the daily `results_time` (3 PM by default) would
  automate this — not included yet.
- App icon / splash crest is a placeholder (`AppLogo` widget) — drop the
  real college crest into `assets/images/` and swap it in.
