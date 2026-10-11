import 'package:dashboard_layout/dashboard_layout.dart'
    show PendingLoginRow, ProfessorLinkRow;
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfessorLinksException implements Exception {
  ProfessorLinksException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Professor identity vs. login email — the Registrar/Admin override. See
/// supabase/add_professor_identity_override.sql for the rules each call
/// enforces (and who may call it).
class ProfessorLinksRepository {
  ProfessorLinksRepository(this._client);

  final SupabaseClient _client;

  Future<({List<ProfessorLinkRow> professors, List<PendingLoginRow> pending})>
      fetch() async {
    try {
      final rows = await _client.rpc('list_professor_links');
      final professors = <ProfessorLinkRow>[];
      final pending = <PendingLoginRow>[];
      for (final raw in rows as List<dynamic>) {
        final r = raw as Map<String, dynamic>;
        if (r['kind'] == 'pending_login') {
          pending.add(PendingLoginRow(
            id: r['id'] as String,
            email: r['email'] as String? ?? '',
            fullName: r['full_name'] as String? ?? '',
          ));
        } else {
          professors.add(ProfessorLinkRow(
            id: r['id'] as String,
            fullName: r['full_name'] as String? ?? '',
            employeeId: r['employee_id'] as String?,
            email: r['email'] as String?,
            claimedEmail: r['claimed_email'] as String?,
            isStub: r['is_stub'] as bool? ?? false,
            nameKey: r['name_key'] as String? ?? '',
            classCount: (r['class_count'] as num?)?.toInt() ?? 0,
          ));
        }
      }
      return (professors: professors, pending: pending);
    } on PostgrestException catch (e) {
      throw ProfessorLinksException(e.message);
    }
  }

  /// Connects, changes or removes a professor's login email. Returns
  /// `linked` (they had already signed in), `stored` (waiting for
  /// first sign-in), `unlinked`, `unchanged` or `cleared`.
  Future<String> connectEmail(
    String professorId,
    String email, {
    String? actorName,
  }) async {
    try {
      final result = await _client.rpc('change_professor_email', params: {
        'p_professor_id': professorId,
        'p_email': email,
        'p_actor_name': actorName,
      });
      return result as String? ?? 'stored';
    } on PostgrestException catch (e) {
      throw ProfessorLinksException(e.message);
    }
  }

  /// Folds exact-duplicate professor records (same name key, no login) into
  /// one. [dryRun] only counts how many would be merged.
  Future<int> mergeDuplicates({bool dryRun = false}) async {
    try {
      final result = await _client
          .rpc('merge_duplicate_professors', params: {'p_dry_run': dryRun});
      return (result as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw ProfessorLinksException(e.message);
    }
  }

  Future<void> linkLogin(String loginId, String professorId) async {
    try {
      await _client.rpc('link_login_to_professor', params: {
        'p_login_id': loginId,
        'p_professor_id': professorId,
      });
    } on PostgrestException catch (e) {
      throw ProfessorLinksException(e.message);
    }
  }

  Future<void> merge(String keepId, String removeId) async {
    try {
      await _client.rpc('merge_professors', params: {
        'p_keep': keepId,
        'p_remove': removeId,
      });
    } on PostgrestException catch (e) {
      throw ProfessorLinksException(e.message);
    }
  }
}
