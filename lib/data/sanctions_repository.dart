import 'package:supabase_flutter/supabase_flutter.dart';

class SanctionsRepositoryException implements Exception {
  SanctionsRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `sanctions.sanction_type`.
enum SanctionType {
  warning('warning', 'Warning'),
  communityService('community_service', 'Community service'),
  suspension('suspension', 'Suspension'),
  nonReadmission('non_readmission', 'Non-readmission'),
  dismissal('dismissal', 'Dismissal'),
  other('other', 'Other');

  const SanctionType(this.value, this.label);
  final String value;
  final String label;

  /// Mirrors the `sanctions_enrollment_type_check` constraint: only these two
  /// block the student's re-enrollment.
  bool get affectsEnrollment => this == nonReadmission || this == dismissal;

  static SanctionType parse(String? value) => SanctionType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => SanctionType.other,
      );
}

/// Whether the sanction follows the student handbook or is decided from the
/// investigation.
enum SanctionBasis {
  handbook('handbook'),
  custom('custom');

  const SanctionBasis(this.value);
  final String value;

  static SanctionBasis parse(String? value) =>
      value == 'handbook' ? handbook : custom;
}

class SanctionInput {
  const SanctionInput({
    required this.violationId,
    required this.basis,
    required this.sanctionType,
    required this.description,
    this.handbookOffenseId,
    this.effectiveOn,
    this.endsOn,
    bool? affectsEnrollment,
    this.overrideReason,
  }) : _affectsEnrollment = affectsEnrollment;

  final String violationId;
  final SanctionBasis basis;
  final SanctionType sanctionType;
  final String description;
  final String? handbookOffenseId;
  final DateTime? effectiveOn;
  final DateTime? endsOn;
  final bool? _affectsEnrollment;

  /// Required (non-empty) when the case is still with Guidance.
  final String? overrideReason;

  bool get affectsEnrollment =>
      _affectsEnrollment ?? sanctionType.affectsEnrollment;
}

class SanctionRecord {
  const SanctionRecord({
    required this.id,
    required this.violationId,
    required this.studentId,
    required this.basis,
    required this.sanctionType,
    required this.description,
    required this.effectiveOn,
    required this.affectsEnrollment,
    required this.decidedAt,
    this.endsOn,
    this.overrideReason,
  });

  final String id;
  final String violationId;
  final String studentId;
  final SanctionBasis basis;
  final SanctionType sanctionType;
  final String description;
  final DateTime effectiveOn;
  final DateTime? endsOn;
  final bool affectsEnrollment;
  final DateTime decidedAt;
  final String? overrideReason;

  factory SanctionRecord.fromRow(Map<String, dynamic> row) => SanctionRecord(
        id: row['id'] as String,
        violationId: row['violation_id'] as String,
        studentId: row['student_id'] as String,
        basis: SanctionBasis.parse(row['basis'] as String?),
        sanctionType: SanctionType.parse(row['sanction_type'] as String?),
        description: row['description'] as String? ?? '',
        effectiveOn: _date(row['effective_on'] as String)!,
        endsOn: _date(row['ends_on'] as String?),
        affectsEnrollment: row['affects_enrollment'] as bool? ?? false,
        decidedAt: DateTime.parse(row['decided_at'] as String).toLocal(),
        overrideReason: row['override_reason'] as String?,
      );

  static DateTime? _date(String? iso) {
    if (iso == null) return null;
    final d = DateTime.parse(iso);
    return DateTime(d.year, d.month, d.day);
  }
}

class SanctionsRepository {
  SanctionsRepository(this._client);

  final SupabaseClient _client;

  /// Records the sanction and closes the case (`record_sanction`). Returns the
  /// new sanction id.
  Future<String> record(SanctionInput input) async {
    try {
      final id = await _client.rpc('record_sanction', params: {
        'p_violation_id': input.violationId,
        'p_basis': input.basis.value,
        'p_handbook_offense_id': input.handbookOffenseId,
        'p_sanction_type': input.sanctionType.value,
        'p_description': input.description,
        'p_effective_on': _formatDate(input.effectiveOn),
        'p_ends_on': _formatDate(input.endsOn),
        'p_affects_enrollment': input.affectsEnrollment,
        'p_override_reason': input.overrideReason,
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw SanctionsRepositoryException(e.message);
    }
  }

  /// Every sanction on a student's record, newest first.
  Future<List<SanctionRecord>> forStudent(String studentId) async {
    try {
      final rows = await _client
          .from('sanctions')
          .select()
          .eq('student_id', studentId)
          .order('decided_at', ascending: false);
      return [
        for (final r in rows as List<dynamic>)
          SanctionRecord.fromRow(r as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      throw SanctionsRepositoryException(e.message);
    }
  }

  static String? _formatDate(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
}
