import 'package:supabase_flutter/supabase_flutter.dart';

/// A parent signed in through the embedded credential login (see
/// supabase/add_parent_credentials.sql) — who they are and which students
/// `parent_student_links` maps to them.
class ParentLogin {
  const ParentLogin({
    required this.parentId,
    required this.displayName,
    required this.email,
    required this.mustChangePassword,
    required this.studentIds,
  });

  final String parentId;
  final String displayName;
  final String email;
  final bool mustChangePassword;
  final List<String> studentIds;
}

/// Outcome of [ParentCredentialRepository.login].
class ParentLoginResult {
  const ParentLoginResult.success(ParentLogin this.login) : deactivated = false;
  const ParentLoginResult.deactivated()
      : login = null,
        deactivated = true;
  const ParentLoginResult.rejected()
      : login = null,
        deactivated = false;

  final ParentLogin? login;
  final bool deactivated;
}

/// One guardian account a batch enrollment just created a temporary password
/// for. The plaintext exists only in memory, long enough for the registrar to
/// see it once — the database keeps a bcrypt hash only.
class GuardianCredential {
  GuardianCredential({
    required this.email,
    required this.guardianName,
    required this.temporaryPassword,
    List<String>? students,
  }) : students = students ?? [];

  final String email;
  final String? guardianName;
  final String temporaryPassword;

  /// "2026-0001 Juan Dela Cruz" labels of the children this guardian was
  /// linked to in the same batch.
  final List<String> students;
}

class ParentCredentialRepository {
  ParentCredentialRepository(this._client);
  final SupabaseClient _client;

  /// Mints a temporary password for [parentId]. Null when a credential
  /// already exists and [reset] is false (the guardian may already have
  /// changed it — a re-upload must not invalidate that).
  Future<String?> issue(String parentId, {bool reset = false}) async {
    final result = await _client.rpc('issue_parent_credential', params: {
      'p_parent_id': parentId,
      'p_reset': reset,
    });
    return result as String?;
  }

  Future<ParentLoginResult> login(String email, String password) async {
    final raw = await _client.rpc('parent_login', params: {
      'p_email': email.trim(),
      'p_password': password,
    });
    if (raw is! Map) return const ParentLoginResult.rejected();
    if (raw['deactivated'] == true) return const ParentLoginResult.deactivated();
    return ParentLoginResult.success(_parse(raw));
  }

  /// Re-reads a remembered parent's name/flags after a reload. Null when the
  /// credential no longer exists or the account was deactivated.
  Future<ParentLogin?> session(String parentId) async {
    final raw = await _client
        .rpc('parent_session', params: {'p_parent_id': parentId});
    if (raw is! Map) return null;
    if (raw['active'] == false) return null;
    return _parse(raw);
  }

  /// False when [oldPassword] is wrong. Throws a [PostgrestException] with a
  /// readable message when [newPassword] breaks the rules.
  Future<bool> changePassword({
    required String parentId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final ok = await _client.rpc('parent_change_password', params: {
      'p_parent_id': parentId,
      'p_old_password': oldPassword,
      'p_new_password': newPassword,
    });
    return ok == true;
  }

  static ParentLogin _parse(Map raw) => ParentLogin(
        parentId: raw['parent_id'] as String,
        displayName: (raw['display_name'] as String?) ?? '',
        email: (raw['email'] as String?) ?? '',
        mustChangePassword: raw['must_change'] == true,
        studentIds: [
          for (final id in (raw['student_ids'] as List?) ?? const [])
            id as String,
        ],
      );
}
