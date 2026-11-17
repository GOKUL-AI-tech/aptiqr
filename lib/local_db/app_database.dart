import 'package:drift/drift.dart';

import 'connection/connection.dart';

part 'app_database.g.dart';

/// Cached copy of today's question paper, written the moment a student
/// starts their attempt so the test can still be answered if the
/// connection drops mid-way. Deliberately excludes `correctOption` —
/// scoring happens server-side.
class CachedQuestions extends Table {
  TextColumn get dailyTestId => text()();
  TextColumn get questionId => text()();
  IntColumn get questionOrder => integer()();
  TextColumn get subject => text()();
  TextColumn get questionText => text()();
  TextColumn get optionA => text()();
  TextColumn get optionB => text()();
  TextColumn get optionC => text()();
  TextColumn get optionD => text()();

  @override
  Set<Column> get primaryKey => {dailyTestId, questionId};
}

/// One row per test the student has started on this device. Mirrors
/// `public.test_attempts` locally so the UI works before the row exists
/// (or is reachable) on the server.
class LocalAttempts extends Table {
  TextColumn get dailyTestId => text()();
  TextColumn get attemptId => text().nullable()(); // filled once the server ack's start_test_attempt
  TextColumn get status => text().withDefault(const Constant('in_progress'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  BoolColumn get pendingSubmit => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {dailyTestId};
}

/// Every answer the student picks, written locally first. `synced`
/// flips to true once `OfflineSyncService` has confirmed the write on
/// Supabase via the `submit_answer` RPC.
class PendingAnswers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get dailyTestId => text()();
  TextColumn get questionId => text()();
  TextColumn get selectedOption => text()(); // A/B/C/D
  TextColumn get clientUuid => text()();
  DateTimeColumn get answeredAt => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {dailyTestId, questionId},
      ];
}

@DriftDatabase(tables: [CachedQuestions, LocalAttempts, PendingAnswers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase();

  @override
  int get schemaVersion => 1;

  Future<void> cacheQuestions(String dailyTestId, List<CachedQuestionsCompanion> rows) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedQuestions, rows);
    });
  }

  Future<List<CachedQuestion>> questionsFor(String dailyTestId) {
    return (select(cachedQuestions)
          ..where((t) => t.dailyTestId.equals(dailyTestId))
          ..orderBy([(t) => OrderingTerm(expression: t.questionOrder)]))
        .get();
  }

  Future<void> upsertAnswer({
    required String dailyTestId,
    required String questionId,
    required String selectedOption,
    required String clientUuid,
  }) async {
    await into(pendingAnswers).insertOnConflictUpdate(
      PendingAnswersCompanion.insert(
        dailyTestId: dailyTestId,
        questionId: questionId,
        selectedOption: selectedOption,
        clientUuid: clientUuid,
        answeredAt: DateTime.now(),
        synced: const Value(false),
      ),
    );
  }

  Future<Map<String, String>> answersFor(String dailyTestId) async {
    final rows = await (select(pendingAnswers)..where((t) => t.dailyTestId.equals(dailyTestId))).get();
    return {for (final r in rows) r.questionId: r.selectedOption};
  }

  Future<List<PendingAnswer>> unsyncedAnswers() {
    return (select(pendingAnswers)..where((t) => t.synced.equals(false))).get();
  }

  Future<void> markSynced(int id) {
    return (update(pendingAnswers)..where((t) => t.id.equals(id))).write(const PendingAnswersCompanion(synced: Value(true)));
  }

  Future<void> upsertLocalAttempt(LocalAttemptsCompanion row) {
    return into(localAttempts).insertOnConflictUpdate(row);
  }

  Future<LocalAttempt?> localAttemptFor(String dailyTestId) {
    return (select(localAttempts)..where((t) => t.dailyTestId.equals(dailyTestId))).getSingleOrNull();
  }

  Future<List<LocalAttempt>> attemptsPendingSubmit() {
    return (select(localAttempts)..where((t) => t.pendingSubmit.equals(true))).get();
  }

  /// Attempts started fully offline (no connectivity at all when
  /// `start_test_attempt` was first tried), so they have no server-side
  /// row yet. [OfflineSyncService] must backfill these via
  /// `start_test_attempt` before any of their answers/submission can sync
  /// — otherwise they'd be stuck forever pointing at a null attempt id.
  ///
  /// Restricted to status = 'in_progress': a cancelled attempt (student
  /// left the app mid-test — see StudentService.cancelAttempt) is also
  /// left with a null attempt id if it never reached the server, but it
  /// must NOT be backfilled — that would call start_test_attempt again
  /// and resurrect a forfeited attempt as a fresh in-progress one.
  Future<List<LocalAttempt>> attemptsMissingServerId() {
    return (select(localAttempts)
          ..where((t) => t.attemptId.isNull() & t.status.equals('in_progress')))
        .get();
  }

  /// Wipes every locally-cached table (today's cached question papers,
  /// in-progress/submitted local attempts, and any not-yet-synced pending
  /// answers). Called from AuthService.signOut() — this SQLite file lives
  /// at getApplicationDocumentsDirectory() and survives a sign-out/
  /// sign-in cycle on the same device by design (that's the whole point
  /// of it being an offline cache), but none of these three tables carry
  /// a student id at all — every query is keyed only by dailyTestId. On
  /// a device reused by more than one student (two students testing
  /// back-to-back on the same phone/emulator, a shared kiosk-style
  /// device, ...) that meant the SECOND student to sign in could be
  /// served the FIRST student's cached attempt status/answers for
  /// whatever test they'd both be looking at (e.g. Home showing "View
  /// Result" for a student who never actually took the test). Clearing
  /// on every sign-out closes that gap for the realistic case — switching
  /// which student is signed in on a device always goes through an
  /// explicit sign-out first, there's no way to reach a different
  /// student's session otherwise.
  ///
  /// Trade-off: if a student signs out with genuinely unsynced local
  /// progress (mid-test answers that haven't reached the server yet),
  /// this discards them. That's judged an acceptable, rare edge case —
  /// there is no "Sign out" control reachable from the actual test-taking
  /// screens (it only lives on the Profile tab), and it's a strict
  /// improvement over the previous behavior of leaking that data to
  /// whoever signs in next regardless.
  Future<void> clearAllForSignOut() async {
    await batch((batch) {
      batch.deleteAll(cachedQuestions);
      batch.deleteAll(localAttempts);
      batch.deleteAll(pendingAnswers);
    });
  }
}

LazyDatabase _openConnection() => openLocalDatabase();
