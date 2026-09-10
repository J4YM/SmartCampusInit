import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:student_portal_module/models/good_moral_request_status.dart';
import 'package:capstone_dashboard/data/student_portal_repository.dart';

void main() {
  test('submitGoodMoralRequest and fetchMyGoodMoralRequests have expected signatures', () {
    final repo = StudentPortalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<void> Function({
      required String studentId,
      required String documentType,
      required String purpose,
      required String requestedBy,
      String? remarks,
    }) submitGoodMoralRequest = repo.submitGoodMoralRequest;
    expect(submitGoodMoralRequest, isNotNull);

    final Future<List<GoodMoralRequestStatus>> Function(String studentId)
        fetchMyGoodMoralRequests = repo.fetchMyGoodMoralRequests;
    expect(fetchMyGoodMoralRequests, isNotNull);
  });
}
