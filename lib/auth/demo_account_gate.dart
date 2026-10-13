import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import 'app_role.dart';
import 'app_user.dart';

const kDeactivatedAccountMessage =
    'This account has been deactivated. Contact an administrator.';

/// The seeded `profiles` rows the static demo accounts (see
/// static_demo_accounts.dart) stand in for — the same ids the dashboards file
/// their activity under. Those rows show up in Admin -> Staff Accounts, so the
/// Access Toggle there writes `profiles.is_active` for them; a demo login has
/// no Supabase session of its own, so without this lookup the toggle could
/// never stop a password sign-in. Keep in sync with the connected pages' own
/// `_demo*ProfileId` constants.
///
/// The administrator is deliberately absent: deactivating the only demo
/// admin would lock everyone out of the screen that can re-activate it.
const _demoProfileIds = <AppRole, String>{
  AppRole.teacher: '00000000-0000-4000-8000-000000000002',
  AppRole.registrar: '00000000-0000-4000-8000-000000000003',
  AppRole.itTechnician: '00000000-0000-4000-8000-000000000099',
};

/// True when [user] is a static demo account whose seeded profile has been
/// deactivated by an Admin. Fails open (false) when Supabase isn't configured
/// or the lookup errors, so an offline demo still signs in.
Future<bool> isDemoAccountDeactivated(
  AppUser user, {
  SupabaseClient? client,
}) async {
  final profileId = _demoProfileIds[user.role];
  if (profileId == null) return false;
  if (client == null && !AppEnv.supabaseConfigured) return false;
  try {
    final row = await (client ?? Supabase.instance.client)
        .from('profiles')
        .select('is_active')
        .eq('id', profileId)
        .maybeSingle();
    return row != null && row['is_active'] == false;
  } catch (_) {
    return false;
  }
}
