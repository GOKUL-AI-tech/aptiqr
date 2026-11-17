import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams a simple online/offline boolean the rest of the app (test-taking
/// flow especially) can react to, wrapping connectivity_plus's more
/// granular connectivity-type stream.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged.map(
        (results) => !results.contains(ConnectivityResult.none),
      );

  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// True whenever the device currently has network connectivity.
/// (Connectivity, not internet reachability — the sync service still
/// treats failed Supabase calls as "stay offline, retry later".)
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.onStatusChange;
});
