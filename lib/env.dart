import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Populated in [AppEnv.resolve] after [loadLocalEnv] runs in `main`.
class AppEnv {
  AppEnv._();

  static String supabaseUrl = '';
  static String supabaseAnonKey = '';
  /// Must match a label of Postgres enum `app_role` exactly (case-sensitive).
  static String profileRoleStudent = 'Student';

  /// Base URL of the deployed dropout-risk prediction service (see
  /// `Behavioral AI Model/src/deployment/prediction_api.py` / API_CONTRACT.md).
  /// No default — empty means "not configured" (see [mlApiConfigured]),
  /// since this service isn't bundled with this app and must be deployed
  /// and pointed at separately.
  static String mlApiBaseUrl = '';

  /// `X-API-Key` header sent to the ML service's `/retrain` and
  /// `/retrain/status` endpoints (see `MlRiskRepository.triggerRetrain`).
  /// No default — empty means retrain is unavailable (the Admin ML &
  /// Thresholds page disables the button rather than sending an unauthed
  /// request). This ships inside the compiled web bundle like every other
  /// `.env` value in this app — see the key's own comment in `.env.example`
  /// for the accepted tradeoff that implies.
  static String mlRetrainApiKey = '';

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
    mlApiBaseUrl = _pick(
      'ML_API_BASE_URL',
      const String.fromEnvironment('ML_API_BASE_URL'),
    );
    mlRetrainApiKey = _pick(
      'ML_RETRAIN_API_KEY',
      const String.fromEnvironment('ML_RETRAIN_API_KEY'),
    );
  }

  static String _pick(String key, String defineFallback) {
    final raw = dotenv.env[key];
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    return defineFallback;
  }

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get mlApiConfigured => mlApiBaseUrl.isNotEmpty;

  static bool get mlRetrainConfigured =>
      mlApiConfigured && mlRetrainApiKey.isNotEmpty;
}
