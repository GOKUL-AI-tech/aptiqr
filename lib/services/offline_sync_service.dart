import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/supabase/supabase_client.dart';
import '../core/utils/connectivity_service.dart';
import '../local_db/app_database.dart';

/// Replays everything answered offline once the device is back online:
/// 1. push each unsynced [PendingAnswer] via the `submit_answer` RPC
/// 2. for any [LocalAttempt] flagged `pendingSubmit`, call
///    `submit_test_attempt` once its answers are all confirmed synced
///
/// `StudentService` writes answers locally first and calls [syncNow]
/// opportunistically; `main`/the student shell also calls it whenever
/// [isOnlineProvider] flips to true, so a student who finishes a test
/// fully offline still gets their result the moment they reconnect.
class OfflineSyncService {
  final AppDatabase _db = AppDatabase.instance;
  final _client = SupabaseService.client;

  // Tracks the in-flight sync so concurrent callers (the opportunistic
  // call from StudentService.answerQuestion, the connectivity listener
  // below, and a student tapping Submit) all await the SAME run instead
  // of a later caller returning instantly while an earlier sync is still
  // writing answers — which used to let submitAttempt proceed against
  // stale local state while a real sync was still in flight.
  Future<void>? _inFlight;

  Future<void> syncNow() {
    return _inFlight ??= _runSync().whenComplete(() => _inFlight = null);
  }

  Future<void> _runSync() async {
    try {
      // Attempts can no longer be created offline (the server validates the
      // rotating QR / device / geofence at start), so there is no backfill.

      final pending = await _db.unsyncedAnswers();
      for (final answer in pending) {
        try {
          await _client.rpc('submit_answer', params: {
            'p_attempt_id': await _resolveAttemptId(answer.dailyTestId),
            'p_question_id': answer.questionId,
            'p_selected_option': answer.selectedOption,
            'p_client_uuid': answer.clientUuid,
            // The moment the student actually tapped, so an answer replayed
            // after reconnecting is judged against the test deadline by when
            // it was given, not when it reached the server.
            'p_answered_at': answer.answeredAt.toUtc().toIso8601String(),
          });
          await _db.markSynced(answer.id);
        } on PostgrestException catch (e) {
          // Permanent rejections (deadline passed / attempt already closed)
          // would otherwise be retried forever.
          final m = e.message.toLowerCase();
          if (m.contains('time is up') || m.contains('already closed') || m.contains('not part of this test')) {
            await _db.markSynced(answer.id);
          }
        } catch (_) {
          // Leave unsynced — will retry on next syncNow() call.
        }
      }

      final pendingSubmits = await _db.attemptsPendingSubmit();
      for (final attempt in pendingSubmits) {
        final stillUnsynced = await _db.unsyncedAnswers();
        final hasUnsyncedForThisTest = stillUnsynced.any((a) => a.dailyTestId == attempt.dailyTestId);
        if (hasUnsyncedForThisTest || attempt.attemptId == null) continue;
        try {
          await _client.rpc('submit_test_attempt', params: {'p_attempt_id': attempt.attemptId});
          await _db.upsertLocalAttempt(LocalAttemptsCompanion(
            dailyTestId: Value(attempt.dailyTestId),
            attemptId: Value(attempt.attemptId),
            status: const Value('submitted'),
            startedAt: Value(attempt.startedAt),
            submittedAt: Value(DateTime.now()),
            pendingSubmit: const Value(false),
          ));
        } catch (_) {
          // Retry later.
        }
      }
    } catch (_) {
      // Any unexpected error in the sync pass itself (not the individual
      // per-item catches above) — swallow so _inFlight still clears via
      // whenComplete and the next connectivity flip/syncNow() call can
      // retry, instead of leaving syncNow() permanently "stuck" on a
      // rejected Future.
    }
  }

  Future<String?> _resolveAttemptId(String dailyTestId) async {
    final local = await _db.localAttemptFor(dailyTestId);
    return local?.attemptId;
  }
}

final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  final service = OfflineSyncService();
  // Re-sync every time connectivity flips back on.
  ref.listen(isOnlineProvider, (previous, next) {
    if (next.valueOrNull == true) {
      service.syncNow();
    }
  });
  return service;
});
