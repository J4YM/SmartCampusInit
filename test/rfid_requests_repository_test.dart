import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/rfid_requests_repository.dart';

void main() {
  test('RfidRequestsRepository methods have the expected signatures', () {
    final repo = RfidRequestsRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<int> Function({
      required List<String> studentIds,
      required String registrarId,
    }) notifyRfidMissing = repo.notifyRfidMissing;
    expect(notifyRfidMissing, isNotNull);

    final Future<List<RfidRequestModel>> Function(String registrarId)
        fetchMyRequests = repo.fetchMyRequests;
    expect(fetchMyRequests, isNotNull);

    final Future<List<RfidRequestModel>> Function() fetchAllRequests =
        repo.fetchAllRequests;
    expect(fetchAllRequests, isNotNull);

    final Future<void> Function(String studentId) markFulfilled =
        repo.markFulfilled;
    expect(markFulfilled, isNotNull);
  });
}
