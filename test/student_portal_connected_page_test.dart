import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/auth/app_user.dart';
import 'package:capstone_dashboard/ui/student_portal_connected_page.dart';

void main() {
  testWidgets('renders the portal home page without Supabase configured',
      (tester) async {
    const user = AppUser(
      id: 'u_student',
      displayName: 'Demo Student',
      role: AppRole.student,
      username: 'student',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: StudentPortalConnectedPage(currentUser: user),
      ),
    );
    await tester.pumpAndSettle();

    // AppEnv.supabaseConfigured is false in this test environment, so the
    // page falls back to StudentPortalHomePage's own mock data rather than
    // hanging on a real fetch — same convention as every other connected
    // page in this codebase.
    expect(find.text('Demo Student'), findsWidgets);
  });
}
