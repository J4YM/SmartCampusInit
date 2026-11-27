import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/professor_colors.dart';

/// A student of this professor who is suspended (or whose suspension starts
/// within the week), with the professor's subjects they are enrolled in. The
/// notice tells the professor not to expect them in class.
class SuspendedStudentNote {
  const SuspendedStudentNote({
    required this.studentName,
    required this.studentNumber,
    required this.subjects,
    required this.startsOn,
    this.endsOn,
  });

  final String studentName;
  final String studentNumber;

  /// The professor's subjects this student is enrolled in.
  final List<String> subjects;
  final DateTime startsOn;

  /// Null for an open-ended suspension.
  final DateTime? endsOn;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Banner listing the professor's suspended students. Renders nothing when
/// there are none.
class SuspensionNotice extends StatelessWidget {
  const SuspensionNotice({super.key, required this.students});

  final List<SuspendedStudentNote> students;

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) return const SizedBox.shrink();
    const accent = Color(0xFFE08A00);
    final text = ProfessorColors.rowText(context);
    final muted = ProfessorColors.mutedText(context);

    return Container(
      key: const Key('suspension-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  students.length == 1
                      ? 'A student in your classes is suspended'
                      : '${students.length} students in your classes are suspended',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in students)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${s.studentName} (${s.studentNumber}) · '
                '${s.endsOn == null ? 'from ${_date(s.startsOn)}, until further notice' : '${_date(s.startsOn)} to ${_date(s.endsOn!)}'}'
                '${s.subjects.isEmpty ? '' : ' · ${s.subjects.join(', ')}'}',
                style: GoogleFonts.poppins(fontSize: 12, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
