import 'package:admin_dashboard/pages/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each password field has its own show/hide eye', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SettingsPage.empty())),
    );
    await tester.pump();
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();

    // Grab the three password fields while they are all still obscured.
    final fields = find
        .byWidgetPredicate((w) => w is TextField && w.obscureText)
        .evaluate()
        .map((e) => e.widget as TextField)
        .toList();
    expect(fields, hasLength(3));
    bool obscured(int i) => (find
            .byWidgetPredicate((w) => w is TextField && w.controller == fields[i].controller)
            .evaluate()
            .single
            .widget as TextField)
        .obscureText;

    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(3));
    expect([for (var i = 0; i < 3; i++) obscured(i)], [true, true, true]);

    // Showing one field leaves the other two hidden.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined).at(1));
    await tester.pump();
    expect([for (var i = 0; i < 3; i++) obscured(i)], [true, false, true]);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(3));
  });
}
