/// Supabase project credentials.
///
/// Supply your own project's URL and anon key at build time:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
/// or  flutter run --dart-define-from-file=env/dev.json
/// (copy env/dev.json.example to env/dev.json and fill it in).
///
/// The anon key is designed to ship inside client apps; access control comes
/// from the Row Level Security policies in supabase/policies.sql.
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR-PROJECT.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty &&
      supabaseAnonKey.trim().isNotEmpty &&
      !supabaseUrl.contains('YOUR-PROJECT') &&
      !supabaseAnonKey.contains('YOUR-ANON-KEY');
}
