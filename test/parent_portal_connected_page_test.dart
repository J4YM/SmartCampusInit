import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/auth/app_user.dart';
import 'package:capstone_dashboard/ui/parent_portal_connected_page.dart';

void main() {
  testWidgets('renders the portal home page without Supabase configured',
      (tester) async {
    const user = AppUser(
      id: 'u_parent',
      displayName: 'Demo Parent',
      role: AppRole.parent,
      username: 'parent.demo',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ParentPortalConnectedPage(currentUser: user),
      ),
    );
    await tester.pumpAndSettle();

    // AppEnv.supabaseConfigured is false in this test environment, so the
    // page falls back to ParentPortalHomePage's own mock data rather than
    // hanging on a real fetch — same convention as every other connected
    // page in this codebase.
    expect(find.byType(ParentPortalHomePage), findsOneWidget);
  });
}
