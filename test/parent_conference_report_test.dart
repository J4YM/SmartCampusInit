import 'dart:convert';

import 'package:capstone_dashboard/documents/parent_conference_report_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

ParentConferenceData _data({
  String status = 'Completed',
  bool? attended,
  String? summary,
  String invitee = 'parent',
}) =>
    ParentConferenceData(
      studentName: 'Juan Dela Cruz',
      studentNumber: '2024-0001',
      section: 'BSIT 3-A',
      scheduledAt: DateTime(2026, 3, 10, 14, 30),
      location: 'Guidance Office',
      invitee: invitee,
      status: status,
      parentAttended: attended,
      summary: summary,
    );

void main() {
  test('builds a PDF document', () async {
    final bytes = await buildParentConferenceReportPdf(
        _data(attended: true, summary: 'Agreed on an attendance plan.'));
    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('builds without a summary or confirmation', () async {
    final bytes = await buildParentConferenceReportPdf(_data());
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('a completed meeting prints as Finished', () {
    expect(_data().statusLabel, 'Finished');
    expect(_data(status: 'Reschedule_Requested').statusLabel,
        'Reschedule requested');
  });

  test('attendance wording covers confirmed, denied and unconfirmed', () {
    expect(_data(attended: true).attendanceLabel, contains('attended'));
    expect(_data(attended: false).attendanceLabel, contains('did not attend'));
    expect(_data().attendanceLabel, 'Not yet confirmed');
  });

  test('says who was invited', () {
    expect(_data().inviteeLabel, 'Parent / guardian');
    expect(_data(invitee: 'both').inviteeLabel,
        'Parent / guardian and student');
  });
}
