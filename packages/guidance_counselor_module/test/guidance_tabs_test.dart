import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

void main() {
  test('student referrals belong to the Discipline Officer, not Guidance', () {
    expect(GuidanceCounselorTab.values.map((t) => t.name), isNot(contains('referrals')));
    expect(GuidanceCounselorTab.values.map((t) => t.name),
        containsAll(['escalationApprovals', 'studentArchive']));
  });
}
