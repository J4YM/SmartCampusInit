import 'package:supabase_flutter/supabase_flutter.dart';

class RfidRequestModel {
  const RfidRequestModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.requestedByName,
    required this.requestedAt,
    required this.isFulfilled,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final String requestedByName;
  final DateTime requestedAt;
  final bool isFulfilled;
}

/// Backs the "students need RFID" request queue — shared by Registrar
/// (submits requests, views their own submission history) and IT
/// Technician (views the full queue, auto-resolves on assignment). See
/// docs/superpowers/specs/2026-09-11-rfid-assignment-requests-design.md.
class RfidRequestsRepository {
  RfidRequestsRepository(this._client);
  final SupabaseClient _client;

  static const _select = '''
    id,
    requested_at,
    status,
    students ( student_number, profiles ( first_name, last_name ), sections ( name ) ),
    profiles ( first_name, last_name )
  ''';

  Future<int> notifyRfidMissing({
    required List<String> studentIds,
    required String registrarId,
  }) async {
    final result = await _client.rpc(
      'notify_rfid_missing',
      params: {'p_student_ids': studentIds, 'p_registrar_id': registrarId},
    );
    return result as int;
  }

  /// Registrar's own submission history — backs "View Logs".
  Future<List<RfidRequestModel>> fetchMyRequests(String registrarId) async {
    final rows = await _client
        .from('rfid_assignment_requests')
        .select(_select)
        .eq('requested_by', registrarId)
        .order('requested_at', ascending: false);
    return _mapRows(rows as List<dynamic>);
  }

  /// The full queue — backs IT Technician's "RFID Requests" tab and
  /// Overview's pending-count stat card.
  Future<List<RfidRequestModel>> fetchAllRequests() async {
    final rows = await _client
        .from('rfid_assignment_requests')
        .select(_select)
        .order('requested_at', ascending: false);
    return _mapRows(rows as List<dynamic>);
  }

  /// Called after a successful RFID assignment in Student Records — a
  /// no-op if no pending request exists for this student.
  Future<void> markFulfilled(String studentId) async {
    await _client
        .from('rfid_assignment_requests')
        .update({
          'status': 'Fulfilled',
          'fulfilled_at': DateTime.now().toIso8601String(),
        })
        .eq('student_id', studentId)
        .eq('status', 'Pending');
  }

  List<RfidRequestModel> _mapRows(List<dynamic> rows) {
    return rows.map((e) {
      final row = e as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final studentProfile = student?['profiles'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;
      final requester = row['profiles'] as Map<String, dynamic>?;
      return RfidRequestModel(
        id: row['id'] as String,
        studentName: _fullName(
          studentProfile?['first_name'] as String?,
          studentProfile?['last_name'] as String?,
        ),
        studentNumber: student?['student_number'] as String? ?? '',
        section: section?['name'] as String? ?? '',
        requestedByName: _fullName(
          requester?['first_name'] as String?,
          requester?['last_name'] as String?,
        ),
        requestedAt: DateTime.parse(row['requested_at'] as String),
        isFulfilled: row['status'] == 'Fulfilled',
      );
    }).toList();
  }

  String _fullName(String? first, String? last) =>
      '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
}
