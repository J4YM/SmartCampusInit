import 'package:flutter_test/flutter_test.dart';

import 'package:capstone_dashboard/auth/app_role.dart';

void main() {
  test('every role has a distinct, short page title', () {
    final titles = {
      for (final role in AppRole.values) role: stiBaliuagTitle(role.titleName),
    };

    expect(titles[AppRole.administrator], 'STI Baliuag - Admin');
    expect(titles[AppRole.registrar], 'STI Baliuag - Registrar');
    expect(titles[AppRole.itTechnician], 'STI Baliuag - IT Technician');
    expect(titles.values.toSet().length, AppRole.values.length);
    for (final title in titles.values) {
      expect(title, startsWith('STI Baliuag - '));
      expect(title, isNot(contains('—')));
    }
  });
}
