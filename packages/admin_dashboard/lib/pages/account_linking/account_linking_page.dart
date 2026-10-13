import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../shared/admin_page_frame.dart';

/// User Management > Account Linking: ties each professor record (created from
/// the course/professor upload) to the Microsoft email they sign in with, and
/// links sign-ins that are waiting for a record. The host supplies the live
/// panel as [content]; without one (no backend) the page says so.
class AccountLinkingPage extends StatelessWidget {
  const AccountLinkingPage({super.key, this.content});

  final Widget? content;

  @override
  Widget build(BuildContext context) {
    return AdminPageFrame(
      title: 'Account Linking',
      subtitle: 'Tie each professor record to the Microsoft email they sign '
          'in with, and link sign-ins that are waiting.',
      child: content ??
          SizedBox(
            width: double.infinity,
            child: BentoCard(
              backgroundColor: DashboardTableColors.card(context),
              borderColor: DashboardTableColors.border(context),
              child: const DashboardTableEmptyState(
                icon: Icons.link_off_rounded,
                message: 'Account linking needs a Supabase connection.',
              ),
            ),
          ),
    );
  }
}
