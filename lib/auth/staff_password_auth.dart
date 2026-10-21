import 'package:discipline_officer_module/discipline_officer_module.dart'
    show validateStrongPassword;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of an email + password sign-in against Supabase Auth.
enum StaffSignInResult {
  /// A Supabase session now exists; the session controller turns it into an
  /// app user (role, approval and deactivation checks included).
  signedIn,

  /// Supabase answered: no such account, or the password is wrong.
  invalidCredentials,

  /// Supabase could not be reached (offline, project down, bad config).
  unavailable,
}

/// Signs a real account (staff, or any user with an email + password in
/// Supabase Auth) in. Guardians are not Supabase users, so for them this
/// reports [StaffSignInResult.invalidCredentials] and the login page tries the
/// guardian flow next.
Future<StaffSignInResult> signInStaffWithPassword(
  SupabaseClient client,
  String email,
  String password,
) async {
  try {
    final response = await client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return response.session == null
        ? StaffSignInResult.invalidCredentials
        : StaffSignInResult.signedIn;
  } on AuthRetryableFetchException {
    // No answer at all (offline, server down): not a verdict on the password.
    return StaffSignInResult.unavailable;
  } on AuthApiException {
    // The server answered and said no (wrong email or password, unconfirmed,
    // rate limited, ...).
    return StaffSignInResult.invalidCredentials;
  } on AuthException {
    return StaffSignInResult.invalidCredentials;
  } catch (_) {
    return StaffSignInResult.unavailable;
  }
}

/// Changes the signed-in account's own password. Returns null on success, or
/// the message to show. The current password is checked first by signing in
/// with it again, so someone at an unlocked screen cannot change it without
/// knowing it. The new password must meet [validateStrongPassword].
Future<String?> changeOwnPassword(
  SupabaseClient client, {
  required String currentPassword,
  required String newPassword,
}) async {
  final user = client.auth.currentUser;
  final email = user?.email;
  if (user == null || email == null || email.isEmpty) {
    return 'Sign in with your email account to change its password.';
  }
  final provider = user.appMetadata['provider'];
  if (provider != null && provider != 'email') {
    return 'This account signs in with Microsoft. Change the password '
        'through your Microsoft account.';
  }

  final policy =
      validateStrongPassword(newPassword, currentPassword: currentPassword);
  if (policy != null) return policy;

  try {
    await client.auth.signInWithPassword(email: email, password: currentPassword);
  } on AuthException {
    return 'Your current password is incorrect.';
  } catch (e) {
    return 'Could not verify your current password: $e';
  }

  try {
    await client.auth.updateUser(UserAttributes(password: newPassword));
    return null;
  } on AuthException catch (e) {
    return e.message;
  } catch (e) {
    return 'Could not change the password: $e';
  }
}
