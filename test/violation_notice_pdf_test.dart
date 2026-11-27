import 'dart:convert';

import 'package:capstone_dashboard/documents/violation_notice_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

ViolationNoticeData _data({
  String sanctionType = 'Suspension',
  DateTime? endsOn,
}) =>
    ViolationNoticeData(
      studentName: 'Juan Dela Cruz',
      studentNumber: '2024-0001',
      section: 'BSIT 3-A',
      offenseTitle: 'No valid ID worn inside campus',
      severity: 'Minor',
      offenseLabel: '2nd Offense',
      behaviorCategory: 'Uniform / Dress Code',
      incidentDate: DateTime(2026, 3, 3),
      incidentNotes: 'Seen without ID at the main gate.',
      sanctionType: sanctionType,
      sanctionDescription: 'Three-day suspension',
      effectiveOn: DateTime(2026, 3, 10),
      endsOn: endsOn,
    );

void main() {
  test('builds a PDF document', () async {
    final bytes = await buildViolationNoticePdf(_data(endsOn: DateTime(2026, 3, 12)));
    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('works without an end date or notes', () async {
    final bytes = await buildViolationNoticePdf(ViolationNoticeData(
      studentName: 'Maria Santos',
      studentNumber: '2024-0002',
      offenseTitle: 'Tardiness',
      severity: 'Minor',
      offenseLabel: '1st Offense',
      incidentDate: DateTime(2026, 3, 3),
      sanctionType: 'Warning',
      sanctionDescription: 'Written warning',
      effectiveOn: DateTime(2026, 3, 3),
    ));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('describes the period for a suspension', () {
    final lines = _data(endsOn: DateTime(2026, 3, 12)).sanctionPeriodText;
    expect(lines, 'March 10, 2026 to March 12, 2026');
    expect(_data().sanctionPeriodText, 'Effective March 10, 2026');
  });
}
