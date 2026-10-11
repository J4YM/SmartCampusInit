import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Staff & Faculty table has a search box. It is a single-line field, and
/// it searches the whole roster through its host (server side) rather than
/// only the rows on screen.
void main() {
  StaffUserModel staff(String id, String name, String email, String dept) =>
      StaffUserModel(
        staffId: id,
        avatarInitials: name.substring(0, 1),
        fullName: name,
        email: email,
        role: StaffRole.teacher,
        department: dept,
        lastLogin: DateTime(2026, 10, 1),
        isActive: true,
        avatarColor: Colors.blue,
      );

  final roster = [
    staff('s1', 'Juan Dela Cruz', 'juan@sti.edu', 'IT'),
    staff('s2', 'Maria Santos', 'maria@sti.edu', 'Business'),
  ];

  Future<void> show(
    WidgetTester tester, {
    ValueChanged<String>? onSearchChanged,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAccountsPage(
          staffList: roster,
          onSearchChanged: onSearchChanged,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('has a search box that is a single-line field', (tester) async {
    await show(tester);
    final field = find.byKey(const Key('staff-search'));
    expect(field, findsOneWidget);

    // A single-line type: Enter submits instead of inserting a newline.
    final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)));
    expect(editable.keyboardType, TextInputType.text);
  });

  testWidgets('Enter never puts a newline in the search text', (tester) async {
    await show(tester);
    final field = find.byKey(const Key('staff-search'));
    await tester.enterText(field, 'juan');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)));
    expect(editable.controller.text, 'juan');
    expect(editable.controller.text.contains('\n'), isFalse);
  });

  testWidgets('without a host the search filters the rows shown',
      (tester) async {
    await show(tester);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('staff-search')), 'maria');
    await tester.pumpAndSettle();
    expect(find.text('Juan Dela Cruz'), findsNothing);
    expect(find.text('Maria Santos'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('staff-search')), 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No staff match your search'), findsOneWidget);
  });

  testWidgets('with a host the search is handed over, not applied locally',
      (tester) async {
    final searches = <String>[];
    await show(tester, onSearchChanged: searches.add);

    await tester.enterText(find.byKey(const Key('staff-search')), 'maria');
    await tester.pumpAndSettle();

    expect(searches, ['maria']);
    // The host re-queries the whole roster; the page does not also filter
    // the (already server-filtered) rows itself.
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
  });
}
