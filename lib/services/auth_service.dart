import 'package:supabase_flutter/supabase_flutter.dart';
// Supabase/gotrue's own `AuthException` (and its subtypes —
// AuthApiException, AuthRetryableFetchException, AuthUnknownException,
// AuthWeakPasswordException, ...) is exported by the plain import above
// too, but this file declares its own `AuthException` class below, which
// (per Dart's shadowing rules) silently wins over the imported one for
// any unprefixed `AuthException` reference in this file. That's fine for
// the local class itself, but this service used to only catch the single
// most common subtype (AuthApiException) when talking to Supabase Auth —
// every sibling type (thrown for network hiccups, malformed responses,
// etc.) fell through uncaught, propagated to the login screens as a raw
// gotrue exception, failed to match their `on AuthException catch` (which
// resolves to *this* file's class, not gotrue's, since the screens never
// import supabase_flutter directly), and landed in their generic
// `catch (e)` as an unhelpful "Something went wrong. Please try again."
// with the real reason thrown away. Importing gotrue's AuthException
// again under a prefix lets this file catch every subtype explicitly.
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue show AuthException, AuthRetryableFetchException;
import '../core/constants/app_constants.dart';
import '../core/supabase/supabase_client.dart';
import '../local_db/app_database.dart';
import '../models/app_profile.dart';
import '../models/user_role.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

const _networkErrorMessage = 'Could not reach the server. Check your internet connection and try again.';

/// Handles sign-in for all three roles plus loading the merged profile
/// once authenticated. Students/faculty are identified by register
/// number / faculty ID, which is resolved to the underlying auth email
/// via the `lookup_*_login_email` RPCs (see supabase/auth_helpers.sql)
/// before calling Supabase Auth's normal email/password sign-in.
class AuthService {
  final SupabaseClient _client = SupabaseService.client;

  Future<AuthResponse> signInStudent({
    required String registerNumber,
    required String password,
  }) async {
    final email = await _lookupEmail('lookup_student_login_email', {
      'p_register_number': registerNumber,
    });
    if (email == null) {
      throw AuthException('No student found with that register number');
    }
    return _signInWithEmail(email, password);
  }

  Future<AuthResponse> signInFaculty({
    required String identifier, // Faculty ID or email
    required String password,
  }) async {
    final email = await _lookupEmail('lookup_faculty_login_email', {
      'p_identifier': identifier,
    });
    if (email == null) {
      throw AuthException('No faculty account found for that ID / email');
    }
    return _signInWithEmail(email, password);
  }

  Future<AuthResponse> signInAdmin({
    required String email,
    required String password,
  }) async {
    return _signInWithEmail(email, password);
  }

  /// Wraps the register-number/faculty-ID → email lookup RPCs. Previously
  /// unwrapped, so a network hiccup here (not just a wrong-credentials
  /// error) surfaced as the generic "Something went wrong" — see the note
  /// above the gotrue import.
  Future<String?> _lookupEmail(String rpcName, Map<String, dynamic> params) async {
    try {
      return await _client.rpc(rpcName, params: params) as String?;
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    } on gotrue.AuthException catch (e) {
      throw AuthException(e.message);
    } catch (_) {
      throw AuthException(_networkErrorMessage);
    }
  }

  Future<AuthResponse> _signInWithEmail(String email, String password) async {
    try {
      return await _client.auth.signInWithPassword(email: email, password: password);
    } on gotrue.AuthRetryableFetchException {
      // .message on this one is just the raw underlying error's
      // toString() (e.g. "ClientException: Failed host lookup..."),
      // not something to show a user directly.
      throw AuthException(_networkErrorMessage);
    } on gotrue.AuthException catch (e) {
      // Catches every other gotrue subtype too (AuthApiException for
      // wrong credentials, AuthUnknownException for a malformed/empty
      // response, ...) — see the note above the gotrue import for why
      // only catching AuthApiException here used to lose real errors.
      throw AuthException(e.message);
    }
  }

  /// Sends the "reset your password" email. Without `redirectTo`, Supabase
  /// falls back to the project's Site URL (a web URL that doesn't exist
  /// for this app), so tapping the link would go nowhere useful — it
  /// needs to come back into the app via the `aptiqr://reset-callback`
  /// deep link instead (see AppConstants.passwordResetRedirectUrl, the
  /// matching Android intent-filter, and ResetPasswordScreen, which the
  /// router forces the user onto once it detects the resulting recovery
  /// session — see GoRouterRefreshStream.needsPasswordReset).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: AppConstants.passwordResetRedirectUrl,
      );
    } on gotrue.AuthRetryableFetchException {
      throw AuthException(_networkErrorMessage);
    } on gotrue.AuthException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Called from ResetPasswordScreen once the user lands back in the app
  /// via the recovery deep link and types a new password.
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on gotrue.AuthRetryableFetchException {
      throw AuthException(_networkErrorMessage);
    } on gotrue.AuthException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> signOut() async {
    // Clear the on-device offline cache/attempt-queue BEFORE actually
    // signing out — see AppDatabase.clearAllForSignOut for why this
    // exists: that SQLite file has no notion of "whose" data is in it,
    // so on a device more than one student signs into (two students
    // testing back-to-back on the same phone/emulator, a shared
    // device, ...) the next student to sign in would otherwise be
    // served whatever attempt/answers/cached questions the previous
    // student left behind for the same test.
    try {
      await AppDatabase.instance.clearAllForSignOut();
    } catch (_) {
      // Non-fatal — still proceed with the actual sign-out below even
      // if clearing the local cache failed for some reason.
    }
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;

  Future<AppProfile?> loadCurrentProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) return null;
    return AppProfile.fromJson(row);
  }

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;
}

/// Convenience for role checks in UI code.
extension AppProfileRoleX on AppProfile? {
  bool get isStudent => this?.role == UserRole.student;
  bool get isFaculty => this?.role == UserRole.faculty;
  bool get isAdmin => this?.role == UserRole.admin;
}
