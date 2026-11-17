import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

/// Thin wrapper around the Supabase singleton so the rest of the app
/// never touches `Supabase.instance` directly.
class SupabaseService {
  SupabaseService._();

  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // Disabled: gotrue's background auto-refresh timer schedules its
        // next tick based on the token's expiry vs. the DEVICE clock. On
        // an emulator/device with a skewed system clock, every token looks
        // perpetually about-to-expire, so the timer fires again almost
        // immediately after each refresh — a self-sustaining loop that
        // spams "Refresh session" and eventually 429s (exactly what we
        // saw). Turning this off removes that background timer entirely,
        // so there's nothing left to loop regardless of clock state.
        // Auth calls still work normally; a session just won't silently
        // auto-renew in the background anymore. Re-enable once the
        // emulator's clock is confirmed correct, if background renewal
        // is wanted for long-idle sessions.
        autoRefreshToken: false,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
  static User? get currentUser => client.auth.currentUser;
}
