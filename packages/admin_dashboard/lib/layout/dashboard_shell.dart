import 'package:dashboard_layout/dashboard_layout.dart';
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
    this.systemOverviewPageBuilder,
    this.staffAccountsPageBuilder,
    this.rfidMappingPageBuilder,
    this.studentDirectoryPageBuilder,
    this.mlThresholdsPageBuilder,
    this.notificationsPageBuilder,
    this.registerSyncsPageBuilder,
    this.reportsExportsPageBuilder,
    this.auditLogsPageBuilder,
    this.initialNotifications,
    this.onMarkNotificationsRead,
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

  final WidgetBuilder? systemOverviewPageBuilder;
  final WidgetBuilder? staffAccountsPageBuilder;
  final WidgetBuilder? rfidMappingPageBuilder;
  final WidgetBuilder? studentDirectoryPageBuilder;
  final WidgetBuilder? mlThresholdsPageBuilder;
  final WidgetBuilder? notificationsPageBuilder;
  final WidgetBuilder? registerSyncsPageBuilder;
  final WidgetBuilder? reportsExportsPageBuilder;
  final WidgetBuilder? auditLogsPageBuilder;

  /// Admin's own notification bell (top of the sidebar) — Admin both sends
  /// notifications (from the Notifications page) and receives some itself.
  /// Falls back to an empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  DashboardRoute _selectedRoute = DashboardRoute.overview;

  void _selectRoute(DashboardRoute route) {
    setState(() => _selectedRoute = route);
  }

  Future<void> _markNotificationsRead() async {
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  void _showNotificationsMenu(BuildContext context) {
    final notifications = widget.initialNotifications ?? const [];
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      // The bell lives at the top of the left Sidebar, not a top-right
      // AppHeaderNavBar like every other dashboard — showHeaderPopover's
      // default anchor math assumes the latter, so center it instead.
      centered: true,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: notifications,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            _markNotificationsRead();
          },
        );
      },
    );
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
            // Distinct from Logout: a plain, no-confirmation-needed way back
            // to the Admin Hub grid, since the sidebar previously had no
            // affordance for that beyond signing all the way out.
            onBackToHub: widget.onReturnToHub,
            unreadNotificationCount: (widget.initialNotifications ?? const [])
                .where((n) => !n.isRead)
                .length,
            onNotificationsTap: () => _showNotificationsMenu(context),
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.mainBackground,
              // Admin has no horizontal tab bar (its persistent nav is the
              // Sidebar to the left, which stays full-height/untouched) —
              // so this wraps just the routed content pane in the same
              // 1440px-capped, centered frame every other module uses.
              // Padding stays zero here since each routed page (system
              // overview, staff accounts, …) already manages its own
              // internal padding.
              child: DashboardPageWrapper(
                padding: EdgeInsets.zero,
                child: MainContentArea(
                  selectedRoute: _selectedRoute,
                  staffAccountsPageBuilder: widget.staffAccountsPageBuilder,
                  rfidMappingPageBuilder: widget.rfidMappingPageBuilder,
                  studentDirectoryPageBuilder: widget.studentDirectoryPageBuilder,
                  mlThresholdsPageBuilder: widget.mlThresholdsPageBuilder,
                  notificationsPageBuilder: widget.notificationsPageBuilder,
                  registerSyncsPageBuilder: widget.registerSyncsPageBuilder,
                  reportsExportsPageBuilder: widget.reportsExportsPageBuilder,
                  auditLogsPageBuilder: widget.auditLogsPageBuilder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
