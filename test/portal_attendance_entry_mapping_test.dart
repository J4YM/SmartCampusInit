import 'package:capstone_dashboard/data/parent_portal_repository.dart'
    as parent;
import 'package:capstone_dashboard/data/student_portal_repository.dart'
    as student;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final classRow = {
    'session_date': '2030-01-07',
    'status': 'Absent',
    'class_section_id': 'c1',
    'class_sections': {
      'subject_id': 'sub1',
      'subjects': {'title': ' Algebra '},
    },
  };
  final legacyRow = {
    'session_date': '2030-01-07',
    'status': 'Present',
    'class_section_id': null,
    'class_sections': null,
  };

  test('parent: class row carries trimmed subject name and id', () {
    final e = parent.attendanceEntryFromRow(classRow);
    expect(e.subjectName, 'Algebra');
    expect(e.subjectId, 'sub1');
  });

  test('parent: legacy row keeps null subject', () {
    final e = parent.attendanceEntryFromRow(legacyRow);
    expect(e.subjectName, isNull);
    expect(e.subjectId, isNull);
  });

  test('student: class row carries trimmed subject name and id', () {
    final e = student.attendanceEntryFromRow(classRow);
    expect(e.subjectName, 'Algebra');
    expect(e.subjectId, 'sub1');
  });

  test('student: legacy row and blank title keep null subject', () {
    expect(student.attendanceEntryFromRow(legacyRow).subjectName, isNull);
    final blank = {
      ...classRow,
      'class_sections': {
        'subject_id': 'sub1',
        'subjects': {'title': '  '},
      },
    };
    expect(student.attendanceEntryFromRow(blank).subjectName, isNull);
  });
}
