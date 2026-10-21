import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _strong = 'Strong#Pass2026!';

Future<void> _openDialog(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Update password'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester,
    {String current = 'OldPass#2026x', String fresh = _strong, String? confirm}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), current);
  await tester.enterText(fields.at(1), fresh);
  await tester.enterText(fields.at(2), confirm ?? fresh);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => ProfileActions.changePassword = null);

  group('validateStrongPassword', () {
    test('accepts a long mixed password', () {
      expect(validateStrongPassword(_strong), isNull);
    });

    test('each rule is enforced with its own message', () {
      expect(validateStrongPassword(''), 'New password is required');
      expect(validateStrongPassword('Sh0rt#pw'),
          'Use at least 12 characters');
      expect(validateStrongPassword('alllowercase#2026'),
          'Add an uppercase letter');
      expect(validateStrongPassword('ALLUPPERCASE#2026'),
          'Add a lowercase letter');
      expect(validateStrongPassword('NoDigitsHere#abc'), 'Add a number');
      expect(validateStrongPassword('NoSymbolsHere2026'), 'Add a symbol');
    });

    test('cannot reuse the current password', () {
      expect(validateStrongPassword(_strong, currentPassword: _strong),
          'Choose a password different from the current one');
    });
  });

  testWidgets('a weak new password is refused before anything is sent',
      (tester) async {
    var calls = 0;
    ProfileActions.changePassword =
        ({required currentPassword, required newPassword}) async {
      calls++;
      return null;
    };
    await _openDialog(tester);
    await _fill(tester, fresh: 'password1');
    await _save(tester);
    expect(find.text('Use at least 12 characters'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a successful change closes the dialog and confirms',
      (tester) async {
    String? sentCurrent, sentNew;
    ProfileActions.changePassword =
        ({required currentPassword, required newPassword}) async {
      sentCurrent = currentPassword;
      sentNew = newPassword;
      return null;
    };
    await _openDialog(tester);
    await _fill(tester);
    await _save(tester);

    expect(sentCurrent, 'OldPass#2026x');
    expect(sentNew, _strong);
    expect(find.text('Save changes'), findsNothing); // dialog closed
    expect(find.text('Password updated'), findsOneWidget);
  });

  testWidgets('a refused change shows the reason and keeps the dialog open',
      (tester) async {
    ProfileActions.changePassword =
        ({required currentPassword, required newPassword}) async =>
            'Your current password is incorrect.';
    await _openDialog(tester);
    await _fill(tester);
    await _save(tester);

    expect(find.text('Your current password is incorrect.'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Password updated'), findsNothing);
  });

  testWidgets('a thrown error is shown, not swallowed', (tester) async {
    ProfileActions.changePassword =
        ({required currentPassword, required newPassword}) async =>
            throw Exception('network down');
    await _openDialog(tester);
    await _fill(tester);
    await _save(tester);
    expect(find.textContaining('network down'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('an account whose password cannot be changed here says so',
      (tester) async {
    ProfileActions.changePassword = null;
    await _openDialog(tester);
    await _fill(tester);
    await _save(tester);
    expect(find.textContaining('cannot be changed here'), findsOneWidget);
    expect(find.text('Password updated'), findsNothing);
  });

  testWidgets('mismatched confirmation is refused', (tester) async {
    var calls = 0;
    ProfileActions.changePassword =
        ({required currentPassword, required newPassword}) async {
      calls++;
      return null;
    };
    await _openDialog(tester);
    await _fill(tester, confirm: '${_strong}x');
    // The Save button stays off until both fields match.
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
