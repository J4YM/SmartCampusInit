import 'package:http/http.dart' as http;
import 'package:kiosk_offline/kiosk_offline.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/discipline_repository.dart';
import '../data/registrar_repository.dart';
import '../env.dart';
import '../models/student_record.dart';

/// Collects every row via keyset paging: [fetch] gets the id of the last row
/// seen (null for the first page) and must return up to [pageSize] rows in a
/// unique, stable id order. Rows are de-duplicated by [idOf], and the loop
/// ends on a short/empty page or when a page adds no new ids, so odd server
/// behaviour can neither duplicate rows nor spin forever.
Future<List<T>> fetchAllKeyset<T>(
  Future<List<T>> Function(String? afterId) fetch,
  String Function(T row) idOf, {
  int pageSize = 500,
}) async {
  final byId = <String, T>{};
  String? after;
  while (true) {
    final rows = await fetch(after);
    final before = byId.length;
    for (final r in rows) {
      byId.putIfAbsent(idOf(r), () => r);
    }
    if (rows.length < pageSize || byId.length == before) break;
    after = idOf(rows.last);
  }
  return byId.values.toList();
}

/// Same select as `StudentsRepository._selectEmbed` (lib/data/students_repository.dart);
/// must keep the shape `StudentRecord.fromSupabase` expects.
const String _studentSelectEmbed = '''
id,
student_number,
rfid_uid,
course,
year_level,
section_id,
photo_path,
guardian_contact_no,
signature_path,
created_at,
profiles (
  first_name,
  last_name,
  role
),
sections (
  name,
  program,
  year_level
),
parent_student_links (
  profiles!parent_student_links_parent_id_fkey (
    first_name,
    last_name
  )
)
''';

/// [KioskRemote] over the existing Supabase RPCs and repositories.
///
/// Error contract with the outbox: a [PostgrestException] that is a business
/// or permission failure becomes [RemoteRejected] (never retried); everything
/// else — socket errors, timeouts, 5xx, PostgREST connection errors — is
/// rethrown as-is and treated as transient.
class SupabaseKioskRemote implements KioskRemote {
  SupabaseKioskRemote(this._client);

  final SupabaseClient _client;

  /// Allow-list of codes that mean "the server understood and refused":
  /// `P0001` (`raise exception` inside `record_rfid_tap`), `42501`
  /// (permission) and classes `22`/`23` (bad data / constraint). Everything
  /// else — every `PGRST*` (JWT expiry, stale schema cache during a
  /// migration, connection errors), 5xx, null — is transient and retried.
  static bool isPermanentPostgrestError(PostgrestException e) {
    final code = e.code ?? '';
    return code == 'P0001' ||
        code == '42501' ||
        code.startsWith('22') ||
        code.startsWith('23');
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
    final students = await fetchAllKeyset<StudentRecord>(
      (afterId) async {
        var q = _client.from('students').select(_studentSelectEmbed);
        if (afterId != null) q = q.gt('id', afterId);
        final rows = await q.order('id').limit(500);
        return [
          for (final r in rows as List<dynamic>)
            StudentRecord.fromSupabase(r as Map<String, dynamic>),
        ];
      },
      (s) => s.id,
    );
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

  /// Reports the kiosk's rejected items to `kiosk_sync_failures` (see
  /// supabase/add_kiosk_sync_failures.sql) for IT Technician / Admin review.
  ///
  /// `ignoreDuplicates` makes this `INSERT ... ON CONFLICT DO NOTHING`, so a
  /// repeated report is a no-op — and the kiosk's anon key only ever needs
  /// INSERT permission, never UPDATE.
  @override
  Future<void> reportFailures(
    String readerUsbSerial,
    List<FailureReport> reports,
  ) async {
    if (reports.isEmpty) return;
    await _client.from('kiosk_sync_failures').upsert(
      [
        for (final r in reports)
          {
            'reader_usb_serial': readerUsbSerial,
            'client_key': r.clientKey,
            'kind': r.kind,
            'rfid_uid': r.rfidUid,
            'student_id': r.studentId,
            'student_name': r.studentName,
            'occurred_at': r.occurredAt.toUtc().toIso8601String(),
            'reason': r.reason,
            'payload': r.payload,
          },
      ],
      onConflict: 'reader_usb_serial,client_key',
      ignoreDuplicates: true,
    );
  }

  @override
  Future<Set<String>> fetchDismissedFailureKeys(String readerUsbSerial) async {
    final rows = await _client
        .from('kiosk_sync_failures')
        .select('client_key')
        .eq('reader_usb_serial', readerUsbSerial)
        .eq('status', 'dismissed');
    return {
      for (final raw in rows as List<dynamic>)
        (raw as Map<String, dynamic>)['client_key'] as String,
    };
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
