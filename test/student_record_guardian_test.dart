import 'package:capstone_dashboard/models/student_record.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String? guardianName,
  String? guardianContactNo,
  List<Map<String, dynamic>> links = const [],
}) =>
    {
      'id': 'stu-1',
      'student_number': '2024-00123',
      'rfid_uid': null,
      'course': 'BS Information Technology',
      'year_level': 3,
      'profiles': {'first_name': 'Juan D.', 'last_name': 'Dela Cruz'},
      'sections': {'name': 'BSIT - 3B'},
      'guardian_name': guardianName,
      'guardian_contact_no': guardianContactNo,
      'parent_student_links': links,
    };

Map<String, dynamic> _link(String first, String last) => {
      'profiles': {'first_name': first, 'last_name': last},
    };

void main() {
  test('a guardian name saved on the student is returned', () {
    final r = StudentRecord.fromSupabase(
      _row(guardianName: '  Maria Dela Cruz ', guardianContactNo: '09171234567'),
    );
    expect(r.guardianName, 'Maria Dela Cruz');
    expect(r.guardianContactNo, '09171234567');
  });

  test('a saved name wins over a linked parent account', () {
    final r = StudentRecord.fromSupabase(
      _row(guardianName: 'Maria Dela Cruz', links: [_link('Pedro', 'Reyes')]),
    );
    expect(r.guardianName, 'Maria Dela Cruz');
  });

  test('with no saved name, the linked parent account is the fallback', () {
    final r = StudentRecord.fromSupabase(
      _row(links: [_link('Pedro', 'Reyes')]),
    );
    expect(r.guardianName, 'Pedro Reyes');
  });

  test('a blank saved name also falls back, and nothing at all is empty', () {
    expect(
      StudentRecord.fromSupabase(
        _row(guardianName: '   ', links: [_link('Pedro', 'Reyes')]),
      ).guardianName,
      'Pedro Reyes',
    );
    final none = StudentRecord.fromSupabase(_row());
    expect(none.guardianName, '');
    expect(none.guardianContactNo, '');
  });
}
