import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../models/staff_profile_record.dart';

class AdminApprovalRepositoryException implements Exception {
  AdminApprovalRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One row of a [AdminApprovalRepository.batchApproveStaff] call: which
/// pending profile gets which role (each pending staffer likely needs a
/// different specific role, so there's no single shared role like
/// [AdminApprovalRepository.approveAllPendingStaff]).
class StaffApproval {
  const StaffApproval({required this.userId, required this.role, this.rfidCardId});

  final String userId;
  final AppRole role;
  final String? rfidCardId;
}

class AdminApprovalRepository {
  AdminApprovalRepository(this._client);

  final SupabaseClient _client;

  static const _profileSelect = 'id, email, first_name, last_name, role, '
      'status, department, phone_number, is_active, last_login_at, '
      'rfid_card_id, created_at';

  Future<List<StaffProfileRecord>> fetchPendingStaff() async {
    final rows = await _client
        .from('profiles')
        .select(_profileSelect)
        .eq('status', 'pending')
        .order('created_at');
    return (rows as List<dynamic>)
        .map((e) => StaffProfileRecord.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  /// Approved, non-student/parent profiles — the roster shown on the Staff
  /// Accounts page.
  Future<List<StaffProfileRecord>> fetchApprovedStaffRoster() async {
    final rows = await _client
        .from('profiles')
        .select(_profileSelect)
        .eq('status', 'approved')
        .not('role', 'in', '(Student,Parent)')
        .order('last_name');
    return (rows as List<dynamic>)
        .map((e) => StaffProfileRecord.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  /// Profiles (pending or approved) with no RFID card linked yet — backs
  /// the RFID Mapping page's "unclaimed profiles" table + fast-assign picker.
  Future<List<StaffProfileRecord>> fetchProfilesMissingRfidCard() async {
    final rows = await _client
        .from('profiles')
        .select(_profileSelect)
        .filter('rfid_card_id', 'is', null)
        .order('created_at');
    return (rows as List<dynamic>)
        .map((e) => StaffProfileRecord.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveStaffMember({
    required String userId,
    required AppRole role,
    String? rfidCardId,
  }) async {
    try {
      await _client.rpc('approve_staff_member', params: {
        'p_user_id': userId,
        'p_role': appRoleToDbValue(role),
        'p_rfid_card_id': rfidCardId,
      });
    } on PostgrestException catch (e) {
      throw AdminApprovalRepositoryException(e.message);
    }
  }

  Future<void> batchApproveStaff(List<StaffApproval> approvals) async {
    try {
      await _client.rpc('batch_approve_staff', params: {
        'p_approvals': approvals
            .map((a) => {
                  'user_id': a.userId,
                  'role': appRoleToDbValue(a.role),
                  'rfid_card_id': a.rfidCardId,
                })
            .toList(),
      });
    } on PostgrestException catch (e) {
      throw AdminApprovalRepositoryException(e.message);
    }
  }

  /// Assigns [role] to every currently-pending staff account. Callers must
  /// confirm this with the admin first (e.g. a dialog) — it's only correct
  /// when a whole pending batch genuinely shares one role.
  Future<int> approveAllPendingStaff({required AppRole role}) async {
    try {
      final result = await _client.rpc('approve_all_pending_staff', params: {
        'p_role': appRoleToDbValue(role),
        'p_confirm': true,
      });
      return (result as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw AdminApprovalRepositoryException(e.message);
    }
  }

  /// Links [rfidCardId] to [profileId]. If that profile is still pending,
  /// [role] is required and the profile is approved in the same call.
  Future<void> linkRfidCard({
    required String profileId,
    required String rfidCardId,
    AppRole? role,
  }) async {
    try {
      await _client.rpc('link_rfid_card', params: {
        'p_profile_id': profileId,
        'p_rfid_card_id': rfidCardId,
        'p_role': role == null ? null : appRoleToDbValue(role),
      });
    } on PostgrestException catch (e) {
      throw AdminApprovalRepositoryException(e.message);
    }
  }

  Future<void> setStaffActive({required String userId, required bool isActive}) async {
    try {
      await _client.from('profiles').update({'is_active': isActive}).eq('id', userId);
    } on PostgrestException catch (e) {
      throw AdminApprovalRepositoryException(e.message);
    }
  }
}
