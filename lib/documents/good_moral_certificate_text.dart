import 'package:discipline_officer_module/discipline_officer_module.dart';

/// One run of text in the Good Moral Certificate's body paragraph — [bold]
/// marks the spans the approved format renders bold (student name, program,
/// enrollment year range).
class CertificateTextSpan {
  const CertificateTextSpan(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) =>
      other is CertificateTextSpan && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => 'CertificateTextSpan($text, bold: $bold)';
}

/// Builds the Good Moral Certificate's body paragraph as a list of text
/// runs, ready to hand straight to `DocxText`/`DocxParagraph` — a plain
/// `String` couldn't carry the bold formatting the approved format requires
/// for the student name, program, and enrollment year range.
///
/// When [activeViolations] is empty, this matches the school's verified
/// wording exactly. When it isn't, generation is no longer blocked — the
/// certificate instead states the student's actual violations on record.
List<CertificateTextSpan> buildGoodMoralCertificationParagraph({
  required String studentName,
  required String program,
  required int? enrollmentYear,
  required int currentYear,
  required List<ActiveViolationSummary> activeViolations,
  List<ActiveViolationSummary> pastViolations = const [],
}) {
  // Pending cases come first, then handled ones: a resolved violation is
  // still part of the student's record and must not disappear from the
  // letter once it has been sanctioned and closed.
  final recordedViolations = [...activeViolations, ...pastViolations];
  final yearRangeSpans = enrollmentYear == null
      ? const <CertificateTextSpan>[]
      : [
          const CertificateTextSpan(' from '),
          CertificateTextSpan('$enrollmentYear-$currentYear.', bold: true),
        ];

  final leadingPunctuation = enrollmentYear == null ? '.' : '';
  final closing = recordedViolations.isEmpty
      ? '$leadingPunctuation Furthermore, the student\'s file does not '
              'indicate any derogatory record or that they had violated any '
              'rule or regulation stipulated in the STI Student Handbook '
              'and is of Good Moral Character.'
      : '$leadingPunctuation Furthermore, the student\'s file indicates the '
              'following record(s) on file with the Office of Student '
              'Affairs and Discipline: ${_formatViolationList(recordedViolations)}. This '
              'certification is issued to reflect the student\'s official '
              'record as of the date below.';

  return [
    const CertificateTextSpan('This is to certify that '),
    CertificateTextSpan(studentName, bold: true),
    const CertificateTextSpan(
      ' has been a student at STI College Baliuag under ',
    ),
    CertificateTextSpan('${program.toUpperCase()} Program', bold: true),
    ...yearRangeSpans,
    CertificateTextSpan(closing),
  ];
}

String _formatViolationList(List<ActiveViolationSummary> violations) {
  return violations.map(_formatViolation).join('; ');
}

String _formatViolation(ActiveViolationSummary v) {
  final details = [
    if (v.loggedOn != null) 'logged ${_formatDate(v.loggedOn!)}',
    if (v.sanction != null && v.sanction!.trim().isNotEmpty)
      'sanction: ${v.sanction!.trim()}',
  ];
  final suffix = details.isEmpty ? '' : ' (${details.join('; ')})';
  return '${v.offenseDescription} — ${v.status}$suffix';
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
