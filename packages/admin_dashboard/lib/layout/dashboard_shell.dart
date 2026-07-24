import 'package:flutter/material.dart';

import '../models/dashboard_route.dart';
import '../theme/app_colors.dart';
import '../widgets/sidebar/sidebar.dart';
import '../pages/main_content_area.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    this.onReturnToHub,
    this.staffAccountsPageBuilder,
    this.rfidMappingPageBuilder,
    this.studentDirectoryPageBuilder,
  });

  /// Invoked from the sidebar's "Logout" action. Wired to the Admin Hub's
  /// back navigation since this build has no separate dashboard sign-out.
  final VoidCallback? onReturnToHub;

  final WidgetBuilder? staffAccountsPageBuilder;
  final WidgetBuilder? rfidMappingPageBuilder;
  final WidgetBuilder? studentDirectoryPageBuilder;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  DashboardRoute _selectedRoute = DashboardRoute.overview;

  void _selectRoute(DashboardRoute route) {
    setState(() => _selectedRoute = route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sidebar(
            selectedRoute: _selectedRoute,
            onRouteSelected: _selectRoute,
            onLogout: widget.onReturnToHub,
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.mainBackground,
              child: MainContentArea(
                selectedRoute: _selectedRoute,
                staffAccountsPageBuilder: widget.staffAccountsPageBuilder,
                rfidMappingPageBuilder: widget.rfidMappingPageBuilder,
                studentDirectoryPageBuilder: widget.studentDirectoryPageBuilder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
