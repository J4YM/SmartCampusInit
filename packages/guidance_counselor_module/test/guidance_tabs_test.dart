import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

void main() {
  test('Guidance has a Referrals tab; investigations belong to the '
      'Discipline Officer', () {
    final names = GuidanceCounselorTab.values.map((t) => t.name).toList();
    expect(names, contains('referrals'));
    expect(names, isNot(contains('investigations')));
    expect(names,
        containsAll(['escalationApprovals', 'referrals', 'studentArchive']));
  });
}
