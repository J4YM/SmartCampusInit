import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/pages/dashboard/registrar_dashboard_page.dart';

/// The Registrar's Professors tab shows the same refined Professor Accounts
/// view the Admin's Account Linking page does — a table card with the waiting
/// sign-ins beside it (stacked on a phone), not the old list of raw cards.
void main() {
  const professors = [
    ProfessorLinkRow(
      id: 'p1',
      fullName: 'Reyes, Ana',
      isStub: false,
      email: 'ana.reyes@baliuag.sti.edu.ph',
      classCount: 4,
    ),
    ProfessorLinkRow(
      id: 'p2',
      fullName: 'Cruz, Ben',
      isStub: true,
      claimedEmail: 'ben.cruz@baliuag.sti.edu.ph',
      classCount: 2,
    ),
  ];

  Future<void> openProfessors(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: RegistrarDashboardPage(
        professorsTabBuilder: (_) => const ProfessorLinksView(
          professors: professors,
          pendingLogins: [
            PendingLoginRow(id: 'l1', email: 'carla.lim@baliuag.sti.edu.ph'),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Professors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professors'));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: the tab shows the table card and the waiting card',
      (tester) async {
    await openProfessors(tester, width: 1500);

    expect(find.text('Professor Accounts'), findsOneWidget);
    expect(find.text('Reyes, Ana'), findsOneWidget);
    expect(find.text('Waiting Sign-ins'), findsOneWidget);
    expect(find.text('carla.lim@baliuag.sti.edu.ph'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone: it renders without overflow', (tester) async {
    await openProfessors(tester, width: 380);

    expect(find.text('Professor Accounts'), findsOneWidget);
    expect(find.text('Waiting Sign-ins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
