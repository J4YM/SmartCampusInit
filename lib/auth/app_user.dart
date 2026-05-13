import 'app_role.dart';

/// Signed-in user for static demo auth. Replace fields when wiring Supabase JWT.
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.role,
    required this.username,
  });

  final String id;
  final String displayName;
  final AppRole role;
  final String username;
}
