import 'package:capstone_dashboard/documents/good_moral_certificate_text.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildGoodMoralCertificationParagraph', () {
    test('clean record, with enrollment year, matches the approved wording',
        () {
      final spans = buildGoodMoralCertificationParagraph(
        studentName: 'KARYLL L. SALAS',
        program: 'BS Hotel Management',
        enrollmentYear: 2020,
        currentYear: 2026,
        activeViolations: const [],
      );

      expect(spans, [
        const CertificateTextSpan('This is to certify that '),
        const CertificateTextSpan('KARYLL L. SALAS', bold: true),
        const CertificateTextSpan(
          ' has been a student at STI College Baliuag under ',
        ),
        const CertificateTextSpan(
          'BS HOTEL MANAGEMENT Program',
          bold: true,
        ),
        const CertificateTextSpan(' from '),
        const CertificateTextSpan('2020-2026.', bold: true),
        const CertificateTextSpan(
          ' Furthermore, the student\'s file does not indicate any '
          'derogatory record or that they had violated any rule or '
          'regulation stipulated in the STI Student Handbook and is of '
          'Good Moral Character.',
        ),
      ]);
    });

    test('clean record, no enrollment year, omits the year-range clause',
        () {
      final spans = buildGoodMoralCertificationParagraph(
        studentName: 'KARYLL L. SALAS',
        program: 'BS Hotel Management',
        enrollmentYear: null,
        currentYear: 2026,
        activeViolations: const [],
      );

      expect(spans, [
        const CertificateTextSpan('This is to certify that '),
        const CertificateTextSpan('KARYLL L. SALAS', bold: true),
        const CertificateTextSpan(
          ' has been a student at STI College Baliuag under ',
        ),
        const CertificateTextSpan(
          'BS HOTEL MANAGEMENT Program',
          bold: true,
        ),
        const CertificateTextSpan(
          '. Furthermore, the student\'s file does not indicate any '
          'derogatory record or that they had violated any rule or '
          'regulation stipulated in the STI Student Handbook and is of '
          'Good Moral Character.',
        ),
      ]);
    });

    test('states a single active violation instead of blocking generation',
        () {
      final spans = buildGoodMoralCertificationParagraph(
        studentName: 'JUAN DELA CRUZ',
        program: 'BS Information Technology',
        enrollmentYear: 2023,
        currentYear: 2026,
        activeViolations: const [
          ActiveViolationSummary(
            offenseDescription:
                'Unauthorized use of mobile phone during class',
            status: 'Pending',
          ),
        ],
      );

      expect(spans, [
        const CertificateTextSpan('This is to certify that '),
        const CertificateTextSpan('JUAN DELA CRUZ', bold: true),
        const CertificateTextSpan(
          ' has been a student at STI College Baliuag under ',
        ),
        const CertificateTextSpan(
          'BS INFORMATION TECHNOLOGY Program',
          bold: true,
        ),
        const CertificateTextSpan(' from '),
        const CertificateTextSpan('2023-2026.', bold: true),
        const CertificateTextSpan(
          ' Furthermore, the student\'s file indicates the following '
          'record(s) on file with the Office of Student Affairs and '
          'Discipline: Unauthorized use of mobile phone during class — '
          'Pending. This certification is issued to reflect the '
          'student\'s official record as of the date below.',
        ),
      ]);
    });

    test('joins multiple active violations with a semicolon separator', () {
      final spans = buildGoodMoralCertificationParagraph(
        studentName: 'JUAN DELA CRUZ',
        program: 'BS Information Technology',
        enrollmentYear: null,
        currentYear: 2026,
        activeViolations: const [
          ActiveViolationSummary(
            offenseDescription: 'Tardiness (habitual) without valid excuse',
            status: 'Pending',
          ),
          ActiveViolationSummary(
            offenseDescription: 'No valid ID worn inside campus',
            status: 'Under_Investigation',
          ),
        ],
      );

      final lastSpan = spans.last;
      expect(
        lastSpan.text,
        '. Furthermore, the student\'s file indicates the following '
        'record(s) on file with the Office of Student Affairs and '
        'Discipline: Tardiness (habitual) without valid excuse — Pending; '
        'No valid ID worn inside campus — Under_Investigation. This '
        'certification is issued to reflect the student\'s official '
        'record as of the date below.',
      );
    });
  });
}
