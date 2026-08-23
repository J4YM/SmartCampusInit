import 'package:supabase_flutter/supabase_flutter.dart';

class AdmissionSlipRepositoryException implements Exception {
  AdmissionSlipRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Everything needed to confirm one admission slip — shared shape for both
/// the student self-report kiosk flow and the Security Personnel report
/// flow, so `submit_admission_slip` behaves identically regardless of who's
/// filing it.
class AdmissionSlipSubmission {
  const AdmissionSlipSubmission({
    required this.slipId,
    required this.studentId,
    required this.reportedBy,
    required this.offenseIds,
    this.isEscalated = false,
    this.notes,
  });

  /// Client-generated up front (before this is ever called) — see
  /// `AdmissionSlipPreviewScreen`'s doc comment for why: it's the same id
  /// already encoded in the QR code the student is looking at.
  final String slipId;
  final String studentId;
  final String reportedBy;
  final List<String> offenseIds;
  final bool isEscalated;
  final String? notes;
}

/// One acknowledged offense on a slip — `fetchSlipDetail`'s per-violation
/// shape.
class AdmissionSlipViolationDetail {
  const AdmissionSlipViolationDetail({
    required this.offenseLabel,
    required this.category,
    required this.status,
  });

  final String offenseLabel;
  final String? category;
  final String status;
}

/// The read-only view `fetchSlipDetail` returns — everything the
/// standalone slip-lookup page (`lib/main_slip.dart`) needs to render,
/// resolved from `admission_slips` + its linked `student_violations` rows.
class AdmissionSlipDetail {
  const AdmissionSlipDetail({
    required this.studentName,
    required this.studentNumber,
    required this.gradeSection,
    required this.reportedByName,
    required this.createdAt,
    required this.violations,
  });

  final String studentName;
  final String studentNumber;
  final String gradeSection;
  final String reportedByName;
  final DateTime createdAt;
  final List<AdmissionSlipViolationDetail> violations;
}

/// Writes admission slips via the `submit_admission_slip` RPC (see
/// supabase/add_admission_slips_schema.sql) — a single transaction across
/// `admission_slips` + every linked `student_violations` row, so a partial
/// failure can never leave one without the other. Also backs the
/// standalone slip-lookup page's read side ([fetchSlipDetail]).
class AdmissionSlipRepository {
  AdmissionSlipRepository(this._client);

  final SupabaseClient _client;

  Future<void> submit(AdmissionSlipSubmission submission) async {
    try {
      await _client.rpc('submit_admission_slip', params: {
        'p_slip_id': submission.slipId,
        'p_student_id': submission.studentId,
        'p_reported_by': submission.reportedBy,
        'p_offense_ids': submission.offenseIds,
        'p_is_escalated': submission.isEscalated,
        if (submission.notes != null && submission.notes!.isNotEmpty)
          'p_incident_notes': submission.notes,
      });
    } on PostgrestException catch (e) {
      throw AdmissionSlipRepositoryException(e.message);
    }
  }

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  /// Returns `null` if [slipId] doesn't match any row — an invalid/expired
  /// link, not an error.
  Future<AdmissionSlipDetail?> fetchSlipDetail(String slipId) async {
    final normalized = slipId.trim();
    if (normalized.isEmpty) return null;

    final slipRow = await _client
        .from('admission_slips')
        .select('''
id,
created_at,
students ( student_number, profiles ( first_name, last_name ), sections ( name ) ),
profiles ( first_name, last_name )
''')
        .eq('id', normalized)
        .maybeSingle();
    if (slipRow == null) return null;

    final student = slipRow['students'] as Map<String, dynamic>?;
    final studentProfile = student?['profiles'] as Map<String, dynamic>?;
    final section = student?['sections'] as Map<String, dynamic>?;
    final reporterProfile = slipRow['profiles'] as Map<String, dynamic>?;

    final violationRows = await _client
        .from('student_violations')
        .select('status, handbook_offenses ( description, category )')
        .eq('admission_slip_id', normalized)
        .order('created_at');

    return AdmissionSlipDetail(
      studentName: _fullName(
        studentProfile?['first_name'] as String?,
        studentProfile?['last_name'] as String?,
      ),
      studentNumber: student?['student_number'] as String? ?? '',
      gradeSection: section?['name'] as String? ?? '',
      reportedByName: _fullName(
        reporterProfile?['first_name'] as String?,
        reporterProfile?['last_name'] as String?,
      ),
      createdAt: DateTime.parse(slipRow['created_at'] as String),
      violations: (violationRows as List<dynamic>).map((raw) {
        final row = raw as Map<String, dynamic>;
        final offense = row['handbook_offenses'] as Map<String, dynamic>?;
        return AdmissionSlipViolationDetail(
          offenseLabel: offense?['description'] as String? ?? 'Unknown offense',
          category: offense?['category'] as String?,
          status: row['status'] as String? ?? 'Pending',
        );
      }).toList(),
    );
  }
}
