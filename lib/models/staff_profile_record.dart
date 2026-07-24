import '../auth/app_role.dart';

/// Row shape from `profiles`, covering both pending and approved staff (and
/// any other profile, e.g. a student, that needs an RFID card linked).
class StaffProfileRecord {
  const StaffProfileRecord({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.status,
    required this.department,
    required this.phoneNumber,
    required this.isActive,
    required this.lastLoginAt,
    required this.rfidCardId,
    required this.createdAt,
  });

  final String id;
  final String? email;
  final String firstName;
  final String lastName;

  /// Null while [status] is [ApprovalStatus.pending] — assigned by an admin
  /// at approval time.
  final AppRole? role;
  final ApprovalStatus status;
  final String? department;
  final String? phoneNumber;
  final bool isActive;
  final DateTime? lastLoginAt;
  final String? rfidCardId;
  final DateTime? createdAt;

  String get fullName {
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    return name.isEmpty ? (email ?? 'Unnamed') : name;
  }

  bool get isPending => status == ApprovalStatus.pending;

  factory StaffProfileRecord.fromSupabase(Map<String, dynamic> row) {
    DateTime? parseDate(dynamic value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return StaffProfileRecord(
      id: row['id'] as String,
      email: row['email'] as String?,
      firstName: (row['first_name'] as String?)?.trim() ?? '',
      lastName: (row['last_name'] as String?)?.trim() ?? '',
      role: appRoleFromDbValue(row['role'] as String?),
      status: approvalStatusFromDbValue(row['status'] as String?),
      department: row['department'] as String?,
      phoneNumber: row['phone_number'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      lastLoginAt: parseDate(row['last_login_at']),
      rfidCardId: row['rfid_card_id'] as String?,
      createdAt: parseDate(row['created_at']),
    );
  }
}
