import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';

import '../models/dashboard_route.dart';
import '../theme/app_colors.dart';
import '../widgets/sidebar/sidebar.dart';
import '../widgets/top_nav_bar.dart';
import '../pages/main_content_area.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    this.onReturnToHub,
    this.onSignOut,
    this.userName,
    this.userEmail,
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
    this.onReportTechnicalIssue,
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

  /// Shown in the sidebar footer in place of the logged-in admin's name and
  /// email. `null` falls back to a generic placeholder (demo behavior).
  final String? userName;
  final String? userEmail;

  final WidgetBuilder? systemOverviewPageBuilder;
  final WidgetBuilder? staffAccountsPageBuilder;
  final WidgetBuilder? rfidMappingPageBuilder;
  final WidgetBuilder? studentDirectoryPageBuilder;
  final WidgetBuilder? mlThresholdsPageBuilder;
  final WidgetBuilder? notificationsPageBuilder;
  final WidgetBuilder? registerSyncsPageBuilder;
  final WidgetBuilder? reportsExportsPageBuilder;
  final WidgetBuilder? auditLogsPageBuilder;

  /// Admin's own notification bell (in [AdminTopNavBar]) — Admin both sends
  /// notifications (from the Notifications page) and receives some itself.
  /// Falls back to an empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  /// Submits a technical-issue report when supplied — see
  /// [ReportTechnicalIssueDialog]. Falls back to no report-issue icon in
  /// [AdminTopNavBar] when omitted.
  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  })? onReportTechnicalIssue;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  DashboardRoute _selectedRoute = DashboardRoute.overview;

  // Local, session-only theme toggle — same pattern as the discipline
  // officer / guidance counselor dashboards' `themeModeController`
  // (ValueNotifier<ThemeMode> toggled from a settings control). Not
  // persisted, matching that precedent.
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  // Sidebar starts full-width; toggled to the icon-only rail via
  // AdminTopNavBar's hamburger button.
  bool _isSidebarCollapsed = false;

  void _selectRoute(DashboardRoute route) {
    setState(() => _selectedRoute = route);
  }

  void _toggleSidebarCollapsed() {
    setState(() => _isSidebarCollapsed = !_isSidebarCollapsed);
  }

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  Future<void> _markNotificationsRead() async {
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  /// True whenever AdminTopNavBar actually renders its report-issue icon —
  /// shifts the bell/email popovers' anchoring left by one icon slot so they
  /// stay under the right icon regardless of whether it's showing.
  bool get _reportIssueIconVisible => widget.onReportTechnicalIssue != null;

  void _showNotificationsMenu(BuildContext context) {
    final notifications = widget.initialNotifications ?? const [];
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      // AdminTopNavBar's action icons sit flush against the pane's true
      // right edge (16px padding, no 1440px cap/centering) — unlike every
      // other dashboard's AppHeaderNavBar, whose default rightMargin math
      // assumes that cap. Override it to match our bar's own layout so the
      // popover lands right under the bell instead of drifting off to where
      // a capped header's edge would have been. The bell is 2 icon-slots in
      // from the right edge when report-issue shows (bell, email, report),
      // or 1 slot in otherwise (bell, email).
      rightMargin: AdminTopNavBar.rightMarginForIcon(
        _reportIssueIconVisible ? 2 : 1,
      ),
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

  void _showEmailMenu(BuildContext context) {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      // Same right-flush trigger as the bell above — see its comment. Email
      // is 1 icon-slot in from the right edge when report-issue shows, or
      // the rightmost icon (slot 0) otherwise.
      rightMargin: AdminTopNavBar.rightMarginForIcon(
        _reportIssueIconVisible ? 1 : 0,
      ),
      contentBuilder: (popoverContext, setPopoverState) {
        return EmailPopover(onViewAll: () => Navigator.of(popoverContext).pop());
      },
    );
  }

  void _showReportIssueDialog(BuildContext context) {
    showReportTechnicalIssueDialog(context,
        onSubmit: widget.onReportTechnicalIssue!);
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
    // Resolves ThemeMode.system against the platform's actual brightness
    // once, using the ambient (pre-Theme) context — the Theme built below
    // then reads as a concrete light/dark brightness everywhere under it.
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system && platformBrightness == Brightness.dark);
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            brightness: isDark ? Brightness.dark : Brightness.light,
            colorSchemeSeed: const Color(0xFF2563EB),
          ),
          // A fresh Builder so `context` below is a descendant of the Theme
          // just constructed — the ValueListenableBuilder's own `context`
          // parameter sits above it and would still resolve to the app's
          // ambient theme, not this toggle.
          child: Builder(builder: (context) => _buildScaffold(context, mode)),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, ThemeMode mode) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sidebar(
            selectedRoute: _selectedRoute,
            onRouteSelected: _selectRoute,
            userName: widget.userName,
            userEmail: widget.userEmail,
            onLogout: () => _confirmLogout(context),
            // Distinct from Logout: a plain, no-confirmation-needed way back
            // to the Admin Hub grid, since the sidebar previously had no
            // affordance for that beyond signing all the way out.
            onBackToHub: widget.onReturnToHub,
            isCollapsed: _isSidebarCollapsed,
            onExpandRequested: () =>
                setState(() => _isSidebarCollapsed = false),
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.mainBackground(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminTopNavBar(
                    onMenuTap: _toggleSidebarCollapsed,
                    unreadNotificationCount:
                        (widget.initialNotifications ?? const [])
                            .where((n) => !n.isRead)
                            .length,
                    onNotificationsTap: () => _showNotificationsMenu(context),
                    onEmailTap: () => _showEmailMenu(context),
                    onReportIssueTap: widget.onReportTechnicalIssue == null
                        ? null
                        : () => _showReportIssueDialog(context),
                  ),
                  // No 1440px cap at this outer level — each routed page
                  // below (System Overview, Staff Accounts, …) owns its own
                  // scroll view and applies the 1440px-capped, centered
                  // frame to just its inner content instead. Capping width
                  // out here would wrap each page's SingleChildScrollView
                  // inside the ConstrainedBox, trapping its scrollbar at the
                  // edge of the centered 1440px column instead of the true
                  // edge of this content pane on wide monitors.
                  Expanded(
                    child: MainContentArea(
                      selectedRoute: _selectedRoute,
                      systemOverviewPageBuilder:
                          widget.systemOverviewPageBuilder,
                      staffAccountsPageBuilder:
                          widget.staffAccountsPageBuilder,
                      rfidMappingPageBuilder: widget.rfidMappingPageBuilder,
                      studentDirectoryPageBuilder:
                          widget.studentDirectoryPageBuilder,
                      mlThresholdsPageBuilder: widget.mlThresholdsPageBuilder,
                      notificationsPageBuilder:
                          widget.notificationsPageBuilder,
                      registerSyncsPageBuilder:
                          widget.registerSyncsPageBuilder,
                      reportsExportsPageBuilder:
                          widget.reportsExportsPageBuilder,
                      auditLogsPageBuilder: widget.auditLogsPageBuilder,
                      themeMode: mode,
                      onThemeModeChanged: (newMode) =>
                          _themeMode.value = newMode,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
