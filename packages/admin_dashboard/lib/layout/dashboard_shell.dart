import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';

import '../models/dashboard_route.dart';
import '../theme/app_colors.dart';
import '../widgets/sidebar/sidebar.dart';
import '../pages/main_content_area.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    this.onReturnToHub,
    this.onSignOut,
    this.staffAccountsPageBuilder,
    this.rfidMappingPageBuilder,
    this.studentDirectoryPageBuilder,
  });

  /// Falls back for the sidebar's "Logout" action (after confirmation) when
  /// [onSignOut] isn't supplied — simply returns to the Admin Hub, so this
  /// package stays independently runnable/demoable without a host session.
  final VoidCallback? onReturnToHub;

  /// Invoked (after confirmation) when the sidebar's "Logout" action should
  /// perform a real sign-out — clearing the host app's session/auth state
  /// and routing to the login screen — rather than just returning to the
  /// Admin Hub. Takes priority over [onReturnToHub] when both are supplied.
  final VoidCallback? onSignOut;

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

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            (widget.onSignOut ?? widget.onReturnToHub)?.call();
          },
        );
      },
    );
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
            onLogout: () => _confirmLogout(context),
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
