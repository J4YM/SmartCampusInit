import 'package:dashboard_layout/dashboard_layout.dart' show GoodMoralFormData;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Good Moral slip filled in from a student's own record: name, student
/// number, section, contact number and the year they started. The school
/// holds no address, middle name or last-attended term, so those stay blank
/// for the student to write. Null when the record cannot be read.
///
/// Used by the Student and Parent portals alike. Reads through
/// `good_moral_prefill` (supabase/add_good_moral_prefill.sql); until that is
/// installed it falls back to reading the tables directly.
Future<GoodMoralFormData?> fetchGoodMoralPrefill(
  SupabaseClient client,
  String studentId,
) async {
  String text(Object? v) => v == null ? '' : '$v'.trim();

  try {
    final rows = await client
        .rpc('good_moral_prefill', params: {'p_student_id': studentId});
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return GoodMoralFormData(
      lastName: text(row['last_name']),
      firstName: text(row['first_name']),
      studentNumber: text(row['student_number']),
      section: text(row['section']),
      contactNumber: text(row['contact_number']),
      ayStarted: text(row['enrollment_year']),
      schoolStatus: 'Enrolled',
    );
  } on PostgrestException {
    // The function is not installed yet: read the tables directly.
  }

  final row = await client
      .from('students')
      .select('student_number, enrollment_year, sections ( name ), '
          'profiles ( first_name, last_name, phone_number )')
      .eq('id', studentId)
      .maybeSingle();
  if (row == null) return null;
  final profile = row['profiles'] as Map<String, dynamic>?;
  return GoodMoralFormData(
    lastName: text(profile?['last_name']),
    firstName: text(profile?['first_name']),
    studentNumber: text(row['student_number']),
    section: text((row['sections'] as Map<String, dynamic>?)?['name']),
    contactNumber: text(profile?['phone_number']),
    ayStarted: text(row['enrollment_year']),
    schoolStatus: 'Enrolled',
  );
}
