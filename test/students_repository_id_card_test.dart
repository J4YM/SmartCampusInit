import 'dart:typed_data';

import 'package:capstone_dashboard/data/students_repository.dart';
import 'package:capstone_dashboard/models/student_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'uploadStudentSignature and fetchStudentSignatureUrl have the '
      'expected signatures', () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = StudentsRepository(client);

    Future<String> Function({
      required String studentId,
      required Uint8List bytes,
    }) uploadStudentSignature = repo.uploadStudentSignature;
    Future<String?> Function(String?) fetchStudentSignatureUrl =
        repo.fetchStudentSignatureUrl;

    expect(uploadStudentSignature, isNotNull);
    expect(fetchStudentSignatureUrl, isNotNull);
  });

  test('create and update accept guardianContactNo', () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = StudentsRepository(client);

    Future<StudentRecord> Function({
      required String studentNumber,
      required String rfidUid,
      required String firstName,
      required String middleInitial,
      required String lastName,
      required String course,
      required int yearLevel,
      required String sectionName,
      required String guardianContactNo,
      String? email,
      String? phoneNumber,
    }) create = repo.create;
    Future<StudentRecord> Function({
      required String id,
      required String studentNumber,
      required String rfidUid,
      required String firstName,
      required String middleInitial,
      required String lastName,
      required String course,
      required int yearLevel,
      required String sectionName,
      required String guardianContactNo,
    }) update = repo.update;

    expect(create, isNotNull);
    expect(update, isNotNull);
  });
}
