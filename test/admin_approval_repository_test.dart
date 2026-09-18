import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/data/admin_approval_repository.dart';
import 'package:capstone_dashboard/models/staff_profile_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('fetchProfilesMissingRfidCard and linkRfidCard have expected signatures', () {
    final repo = AdminApprovalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<StaffProfileRecord>> Function()
        fetchProfilesMissingRfidCard = repo.fetchProfilesMissingRfidCard;
    expect(fetchProfilesMissingRfidCard, isNotNull);

    final Future<void> Function({
      required String profileId,
      required String rfidCardId,
      AppRole? role,
    }) linkRfidCard = repo.linkRfidCard;
    expect(linkRfidCard, isNotNull);
  });
}
