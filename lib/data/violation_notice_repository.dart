import 'package:supabase_flutter/supabase_flutter.dart';

import '../documents/violation_notice_pdf.dart';

/// "1st", "2nd", "3rd", "4th"... (11th, 12th and 13th included).
String ordinalLabel(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// Minor offenses count against Minor, every Major A-D against Major.
bool _isMajor(String? category) =>
    (category ?? '').toLowerCase().startsWith('major');

/// The 1-based offense number of [violationId] among a student's violations,
/// counted within its Minor or Major group by date filed. [violations] is
/// `(id, createdAt, category)` for the student's non-archived violations.
int offenseNumberFor(
  String violationId,
  List<({String id, DateTime createdAt, String? category})> violations,
) {
  final target = violations.where((v) => v.id == violationId).firstOrNull;
  if (target == null) return 1;
  final major = _isMajor(target.category);
  return violations
          .where((v) =>
              _isMajor(v.category) == major &&
              !v.createdAt.isAfter(target.createdAt) &&
              v.id != violationId)
          .length +
      1;
}

/// Loads what the Parent Acknowledgment notice prints for one sanction.
class ViolationNoticeRepository {
  ViolationNoticeRepository(this._client);

  final SupabaseClient _client;

  static const _behaviorLabels = {
    'Academic_Integrity': 'Academic Integrity',
    'Attendance_Tardiness': 'Attendance / Tardiness',
    'Uniform_Dress_Code': 'Uniform / Dress Code',
    'Property_Damage': 'Property / Facility Damage',
    'Disruptive_Conduct': 'Behavioral / Disruptive Conduct',
    'Digital_Device_Policy': 'Digital / Device Policy',
    'Other': 'Other',
  };

  Future<ViolationNoticeData> fetch(String sanctionId) async {
    final sanction = await _client
        .from('sanctions')
        .select('violation_id, student_id, sanction_type, description, '
            'effective_on, ends_on')
        .eq('id', sanctionId)
        .single();

    final violationId = sanction['violation_id'] as String;
    final studentId = sanction['student_id'] as String;

    Map<String, dynamic> violation;
    try {
      violation = await _violationRow(violationId, withBehavior: true);
    } on PostgrestException {
      // behavior_category not migrated yet (supabase/add_defense_revisions.sql).
      violation = await _violationRow(violationId, withBehavior: false);
    }

    final all = await _client
        .from('student_violations')
        .select('id, created_at, handbook_offenses ( category )')
        .eq('student_id', studentId)
        .filter('archived_at', 'is', null);
    final history = [
      for (final raw in all as List<dynamic>)
        (
          id: (raw as Map<String, dynamic>)['id'] as String,
          createdAt: DateTime.parse(raw['created_at'] as String),
          category: (raw['handbook_offenses']
              as Map<String, dynamic>?)?['category'] as String?,
        ),
    ];

    final offense = violation['handbook_offenses'] as Map<String, dynamic>?;
    final student = violation['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    final section = student?['sections'] as Map<String, dynamic>?;
    final category = offense?['category'] as String?;
    final behavior = (violation['behavior_category'] as String?) ??
        (offense?['behavior_category'] as String?);
    final name = [
      (profile?['first_name'] as String? ?? '').trim(),
      (profile?['last_name'] as String? ?? '').trim(),
    ].where((p) => p.isNotEmpty).join(' ');

    return ViolationNoticeData(
      studentName: name.isEmpty ? 'Student' : name,
      studentNumber: student?['student_number'] as String? ?? '',
      section: section?['name'] as String? ?? '',
      offenseTitle: offense?['description'] as String? ?? 'Violation',
      severity: (category ?? 'Unclassified').replaceAll('_', ' '),
      offenseLabel:
          '${ordinalLabel(offenseNumberFor(violationId, history))} Offense',
      behaviorCategory: behavior == null
          ? null
          : (_behaviorLabels[behavior] ?? behavior),
      incidentDate: DateTime.parse(
              (violation['incident_at'] ?? violation['created_at']) as String)
          .toLocal(),
      incidentNotes: violation['incident_notes'] as String? ?? '',
      sanctionType: _typeLabel(sanction['sanction_type'] as String?),
      sanctionDescription: sanction['description'] as String? ?? '',
      effectiveOn: _date(sanction['effective_on'] as String)!,
      endsOn: _date(sanction['ends_on'] as String?),
    );
  }

  Future<Map<String, dynamic>> _violationRow(
    String violationId, {
    required bool withBehavior,
  }) async {
    final select = 'created_at, incident_notes, '
        '${withBehavior ? 'behavior_category, ' : ''}'
        'handbook_offenses ( description, category'
        '${withBehavior ? ', behavior_category' : ''} ), '
        'students ( student_number, profiles ( first_name, last_name ), '
        'sections ( name ) )';
    try {
      return await _client
          .from('student_violations')
          .select('incident_at, $select')
          .eq('id', violationId)
          .single();
    } on PostgrestException catch (e) {
      // incident_at only exists once the lifecycle migration has run.
      if (!e.message.contains('incident_at')) rethrow;
      return _client
          .from('student_violations')
          .select(select)
          .eq('id', violationId)
          .single();
    }
  }

  static String _typeLabel(String? type) {
    switch (type) {
      case 'warning':
        return 'Warning';
      case 'community_service':
        return 'Community service';
      case 'suspension':
        return 'Suspension';
      case 'non_readmission':
        return 'Non-readmission';
      case 'dismissal':
        return 'Dismissal';
      default:
        return 'Other';
    }
  }

  static DateTime? _date(String? iso) {
    if (iso == null) return null;
    final d = DateTime.parse(iso);
    return DateTime(d.year, d.month, d.day);
  }
}
