import 'package:capstone_dashboard/data/guidance_counselor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

/// The analysis reads violation AGGREGATES (counts per category and the last
/// date) through `analysis_violation_counts`, never the violation rows
/// themselves (supabase/add_analysis_aggregates.sql).
void main() {
  late RecordingServer server;
  late SupabaseClient client;

  setUp(() async {
    server = RecordingServer();
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  Iterable<RecordedRequest> violationRowReads() => server.requests.where((r) =>
      r.method == 'GET' && r.path.endsWith('/rest/v1/student_violations'));

  final lastWeek = DateTime.now().subtract(const Duration(days: 7));

  (int, Object?)? answer(RecordedRequest r) {
    if (r.path.endsWith('/rpc/analysis_violation_counts')) {
      return (200, [
        {
          'student_id': 's1',
          'category': 'Minor',
          'violation_count': 2,
          'last_at': lastWeek.toUtc().toIso8601String(),
        },
        {
          'student_id': 's1',
          'category': 'Major_B',
          'violation_count': 1,
          'last_at': lastWeek.subtract(const Duration(days: 3)).toUtc().toIso8601String(),
        },
        {
          'student_id': 's2',
          'category': 'Major_A',
          'violation_count': 1,
          'last_at': lastWeek.toUtc().toIso8601String(),
        },
      ]);
    }
    if (r.path.endsWith('/rest/v1/attendance_records')) {
      return (200, [
        {'student_id': 's1', 'status': 'Present', 'session_date': '2026-10-01'},
        {'student_id': 's1', 'status': 'Absent', 'session_date': '2026-10-02'},
        {'student_id': 's2', 'status': 'Present', 'session_date': '2026-10-01'},
      ]);
    }
    if (r.path.endsWith('/rest/v1/students')) {
      return (200, [
        {'id': 's1', 'student_number': '24-0001', 'course': 'BSIT'},
        {'id': 's2', 'student_number': '24-0002', 'course': 'BSIT'},
      ]);
    }
    return null;
  }

  test('the single-student autofill counts violations from the aggregate',
      () async {
    server.respond = (r) =>
        r.path.endsWith('/rest/v1/attendance_records')
            ? (200, [
                {'status': 'Present', 'session_date': '2026-10-01'}
              ])
            : answer(r);

    final autofill =
        await GuidanceCounselorRepository(client).fetchStudentRiskAutofill('s1');

    expect(autofill.minorCount, 2);
    expect(autofill.majorBCount, 1);
    expect(autofill.majorACount, 0);
    expect(autofill.daysSinceLastViolation, inInclusiveRange(6, 7));

    final call = server.requestTo('/rpc/analysis_violation_counts').json;
    expect(call['p_student_id'], 's1');
    expect(call['p_resolved_only'], isTrue);
    expect(violationRowReads(), isEmpty,
        reason: 'violation rows are not read by the analysis');
  });

  test('the batch analysis counts each student from one aggregate call',
      () async {
    server.respond = answer;

    final records =
        await GuidanceCounselorRepository(client).fetchAllStudentsForBatchAnalysis();

    final s1 = records.firstWhere((r) => r.studentId == '24-0001');
    final s2 = records.firstWhere((r) => r.studentId == '24-0002');
    expect(s1.minorCount, 2);
    expect(s1.majorBCount, 1);
    expect(s2.majorACount, 1);
    expect(s2.minorCount, 0);

    expect(
        server.requests
            .where((r) => r.path.endsWith('/rpc/analysis_violation_counts')),
        hasLength(1));
    expect(server.requestTo('/rpc/analysis_violation_counts').json['p_student_id'],
        isNull);
    expect(violationRowReads(), isEmpty);
  });

  test('a student with no counted violations reads as none on file', () async {
    server.respond = (r) =>
        r.path.endsWith('/rpc/analysis_violation_counts') ? (200, <dynamic>[]) : answer(r);

    final records =
        await GuidanceCounselorRepository(client).fetchAllStudentsForBatchAnalysis();

    final s1 = records.firstWhere((r) => r.studentId == '24-0001');
    expect(s1.minorCount, 0);
    expect(s1.daysSinceLastViolation, 999);
  });

  test('the parent-intervention context counts the window from the aggregate',
      () async {
    server.respond = (r) {
      if (r.path.endsWith('/rest/v1/students')) {
        return (200, {
          'id': 's1',
          'guardian_contact_no': '09171234567',
          'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
        });
      }
      return answer(r);
    };

    final context = await GuidanceCounselorRepository(client)
        .fetchParentInterventionContext('24-0001', windowDays: 30);

    expect(context!.violationCount, 3);
    expect(context.hasMajorViolation, isTrue);
    final call = server.requestTo('/rpc/analysis_violation_counts').json;
    expect(call['p_student_id'], 's1');
    expect(call['p_resolved_only'], isFalse,
        reason: 'the intervention suggestion counts open reports too');
    expect(violationRowReads(), isEmpty);
  });
}
