import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase/supabase_client.dart';
import '../models/admin_profile.dart';
import '../models/app_profile.dart';
import '../models/faculty.dart';
import '../models/student.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Raw Supabase auth state stream — router listens to this to decide
/// whether to show the auth flow or the role-scoped shell.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).onAuthStateChange;
});

final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateChangesProvider).valueOrNull;
  return authState?.session?.user.id ?? SupabaseService.currentUser?.id;
});

/// The signed-in user's merged profile (role + name). Re-fetches only when
/// the signed-in *user id* actually changes (sign in / sign out / switching
/// accounts) — deliberately does NOT watch authStateChangesProvider
/// directly. That stream also emits on routine token-refresh events (which
/// can fire in rapid bursts if any auth API call is made while a token
/// looks near-expiry), and watching it directly here caused this provider
/// to refetch — and the whole Profile screen to tear down and rebuild —
/// on every single one of those, which in turn remounted a widget that
/// itself made an auth API call, re-triggering another refresh. Depending
/// only on currentUserIdProvider breaks that loop: its value (the uid
/// string) is unchanged across token refreshes for the same user, and
/// Riverpod skips notifying dependents when a provider's value doesn't
/// actually change.
final currentProfileProvider = FutureProvider<AppProfile?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return ref.read(authServiceProvider).loadCurrentProfile();
});

/// Student-only extension row, fetched once the base profile confirms role.
final currentStudentProvider = FutureProvider<StudentProfile?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null || profile.role.name != 'student') return null;
  final row = await SupabaseService.client
      .from('students')
      .select('*, profiles(full_name, email)')
      .eq('id', profile.id)
      .maybeSingle();
  if (row == null) return null;
  return StudentProfile.fromJson(row);
});

/// Faculty-only extension row.
final currentFacultyProvider = FutureProvider<FacultyProfile?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null || profile.role.name != 'faculty') return null;
  final row = await SupabaseService.client
      .from('faculty')
      .select('*, profiles(full_name, email)')
      .eq('id', profile.id)
      .maybeSingle();
  if (row == null) return null;
  return FacultyProfile.fromJson(row);
});

/// Admin-only extension row — carries which category (Aptitude/
/// Technical/Communication) this admin login manages. Every admin
/// screen that scopes a query/mutation to "my own category" reads this.
final currentAdminProvider = FutureProvider<AdminProfile?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null || profile.role.name != 'admin') return null;
  final row = await SupabaseService.client
      .from('admins')
      .select('*, profiles(full_name, email)')
      .eq('id', profile.id)
      .maybeSingle();
  if (row == null) return null;
  return AdminProfile.fromJson(row);
});
