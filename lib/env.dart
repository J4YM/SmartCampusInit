import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Populated in [AppEnv.resolve] after [loadLocalEnv] runs in `main`.
class AppEnv {
  AppEnv._();

  static String supabaseUrl = '';
  static String supabaseAnonKey = '';
  /// Must match a label of Postgres enum `app_role` exactly (case-sensitive).
  static String profileRoleStudent = 'Student';

  /// Prefer `.env` keys, then `--dart-define` compile-time values.
  static void resolve() {
    supabaseUrl = _pick(
      'SUPABASE_URL',
      const String.fromEnvironment('SUPABASE_URL'),
    );
    supabaseAnonKey = _pick(
      'SUPABASE_ANON_KEY',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    profileRoleStudent = _pick(
      'PROFILE_ROLE_STUDENT',
      const String.fromEnvironment(
        'PROFILE_ROLE_STUDENT',
        defaultValue: 'Student',
      ),
    );
  }

  static String _pick(String key, String defineFallback) {
    final raw = dotenv.env[key];
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    return defineFallback;
  }

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
