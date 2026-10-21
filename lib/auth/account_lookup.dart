import 'package:supabase_flutter/supabase_flutter.dart';

import 'static_demo_accounts.dart';

/// Whether [username] belongs to an account: a built-in demo login, or (via
/// `login_account_exists`, see supabase/add_login_account_exists.sql) an email
/// of a real account or guardian.
///
/// Used by the sign-in lockout so that typing a name nobody owns is not counted
/// as a failed attempt. If the database cannot answer (offline, the SQL not
/// installed yet) this assumes the account exists, so the lockout keeps
/// counting rather than silently switching off.
Future<bool> loginAccountExists(SupabaseClient? client, String username) async {
  final name = username.trim().toLowerCase();
  if (name.isEmpty) return false;
  if (StaticDemoAccounts.byUsername(name) != null) return true;
  if (client == null) return false;
  try {
    final result =
        await client.rpc('login_account_exists', params: {'p_username': name});
    return result == true;
  } catch (_) {
    return true;
  }
}
