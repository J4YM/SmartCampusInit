import 'package:http/http.dart' as http;
import 'package:kiosk_offline/kiosk_offline.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/discipline_repository.dart';
import '../data/registrar_repository.dart';
import '../data/students_repository.dart';
import '../env.dart';

/// [KioskRemote] over the existing Supabase RPCs and repositories.
///
/// Error contract with the outbox: a [PostgrestException] that is a business
/// or permission failure becomes [RemoteRejected] (never retried); everything
/// else — socket errors, timeouts, 5xx, PostgREST connection errors — is
/// rethrown as-is and treated as transient.
class SupabaseKioskRemote implements KioskRemote {
  SupabaseKioskRemote(this._client);

  final SupabaseClient _client;

  /// `raise exception` inside `record_rfid_tap` surfaces as `P0001`.
  static bool isPermanentPostgrestError(PostgrestException e) {
    final code = e.code ?? '';
    if (code == 'P0001' || code == '42501') return true;
    if (code.startsWith('22') || code.startsWith('23')) return true;
    if (code.startsWith('PGRST')) {
      const connection = {'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003'};
      return !connection.contains(code);
    }
    return false;
  }

  @override
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  }) async {
    try {
      final rows = await _client.rpc('record_rfid_tap', params: {
        'p_reader_usb_serial': readerUsbSerial,
        'p_rfid_uid': rfidUid,
        'p_tapped_at': tappedAt.toUtc().toIso8601String(),
      });
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      return RemoteTapResult(
        tapId: row['tap_id'] as String,
        studentId: row['student_id'] as String?,
        direction: row['tap_direction'] as String,
        tappedAt: DateTime.parse(row['tapped_at'] as String),
      );
    } on PostgrestException catch (e) {
      if (isPermanentPostgrestError(e)) throw RemoteRejected(e.message);
      rethrow;
    }
  }

  @override
  Future<void> submitSlip(SlipSubmission slip) async {
    try {
      await _client.rpc('submit_admission_slip', params: {
        'p_slip_id': slip.slipId,
        'p_student_id': slip.studentId,
        'p_reported_by': slip.reportedBy,
        'p_offense_ids': slip.offenseIds,
        'p_is_escalated': slip.isEscalated,
        if (slip.notes != null && slip.notes!.isNotEmpty)
          'p_incident_notes': slip.notes,
        if (slip.professorId != null && slip.professorId!.isNotEmpty)
          'p_professor_id': slip.professorId,
      });
    } on PostgrestException catch (e) {
      // Duplicate slip id: an earlier attempt already landed (e.g. the app
      // died before the outbox row was deleted). Treat as delivered.
      if (e.code == '23505') return;
      if (isPermanentPostgrestError(e)) throw RemoteRejected(e.message);
      rethrow;
    }
  }

  @override
  Future<ReferenceData> fetchReferenceData() async {
    final students = await StudentsRepository(_client).fetchAll();
    final offenses = await DisciplineRepository(_client).fetchOffenseOptions();
    final teachers = await RegistrarRepository(_client).fetchTeachers();
    final staffRows = await _client
        .from('profiles')
        .select('id, first_name, last_name, role, status, rfid_card_id')
        .not('rfid_card_id', 'is', null)
        .eq('status', 'approved');

    final staff = <OfflineStaff>[];
    for (final raw in staffRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final role = row['role'] as String?;
      final card = (row['rfid_card_id'] as String?)?.trim() ?? '';
      // Same exclusions as StudentsRepository.fetchStaffByRfidCardId.
      if (role == null ||
          card.isEmpty ||
          role == AppEnv.profileRoleStudent ||
          role == 'Parent') {
        continue;
      }
      final first = (row['first_name'] as String?) ?? '';
      final last = (row['last_name'] as String?) ?? '';
      staff.add(OfflineStaff(
        id: row['id'] as String,
        rfidCardId: card,
        fullName: '${first.trim()} ${last.trim()}'.trim(),
        role: role,
      ));
    }

    return ReferenceData(
      students: [
        for (final s in students)
          OfflineStudent(
            id: s.id,
            rfidUid: s.rfidUid.trim(),
            fullName: s.fullName,
            studentNumber: s.studentNumber,
            gradeSection: '${s.yearLevel} - ${s.section}',
            course: s.course,
          ),
      ],
      staff: staff,
      offenses: [
        for (final o in offenses)
          OfflineOffense(id: o.id, label: o.label, category: o.category),
      ],
      teachers: [
        for (final t in teachers)
          OfflineTeacher(id: t.id, fullName: t.fullName),
      ],
    );
  }

  /// Any HTTP response from the REST endpoint (even 401) proves the server
  /// is reachable; a socket error or timeout does not.
  @override
  Future<bool> ping() async {
    try {
      final res = await http
          .get(
            Uri.parse('${AppEnv.supabaseUrl}/rest/v1/'),
            headers: {'apikey': AppEnv.supabaseAnonKey},
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
