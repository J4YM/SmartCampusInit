import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/dashboard_route.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'sidebar_accordion.dart';
import 'sidebar_footer.dart';
import 'sidebar_header.dart';
import 'sidebar_nav_item.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.selectedRoute,
    required this.onRouteSelected,
    this.userName,
    this.userEmail,
    this.onLogout,
    this.onBackToHub,
    this.isCollapsed = false,
    this.onExpandRequested,
  });

  final DashboardRoute selectedRoute;
  final ValueChanged<DashboardRoute> onRouteSelected;

  /// Shown in [SidebarFooter]. Falls back to a placeholder when not
  /// supplied (demo behavior, e.g. running this package standalone).
  final String? userName;
  final String? userEmail;

  /// Falls back to a "Logout tapped" snackbar when not supplied.
  final VoidCallback? onLogout;

  /// Forwarded to [SidebarHeader]'s back-arrow — see its doc comment.
  final VoidCallback? onBackToHub;

  /// True to render as the icon-only rail instead of the full-width sidebar.
  /// Toggled from [AdminTopNavBar]'s hamburger button, not from here.
  final bool isCollapsed;

  /// Invoked when a collapsed accordion group is tapped — expected to
  /// un-collapse the sidebar from the parent (e.g. set [isCollapsed] false).
  final VoidCallback? onExpandRequested;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _userManagementExpanded = true;
  bool _systemConfigExpanded = true;

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: any nested ListTile/ExpansionTile/Text that omits an
    // explicit GoogleFonts.poppins() style still resolves to real Poppins —
    // not a system fallback — because it inherits from this local Theme
    // instead of the ambient one.
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: widget.isCollapsed
            ? AppDimensions.sidebarCollapsedWidth
            : AppDimensions.sidebarWidth,
        color: AppColors.sidebarBackground,
        // Reads the *actual*, currently-animating width rather than
        // widget.isCollapsed directly: on tap, this widget rebuilds
        // immediately with the new target isCollapsed, but the
        // AnimatedContainer's width tweens toward it over 200ms. Switching
        // every child's layout style off the boolean the instant it flips
        // would render (e.g.) the full-width footer's row inside a
        // still-collapsed ~80px-wide container mid-transition, overflowing
        // every frame until the width caught up. Deriving the style from
        // the live width instead keeps content and available space always
        // in sync, frame by frame.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCollapsed = constraints.maxWidth <
                (AppDimensions.sidebarWidth +
                        AppDimensions.sidebarCollapsedWidth) /
                    2;
            return _buildBody(context, isCollapsed);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isCollapsed) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SidebarHeader(
            onBackToHub: widget.onBackToHub,
            isCollapsed: isCollapsed,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.sidebarDivider,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SidebarNavItem(
                  label: 'Overview',
                  icon: Icons.dashboard_outlined,
                  isSelected: widget.selectedRoute == DashboardRoute.overview,
                  onTap: () => widget.onRouteSelected(DashboardRoute.overview),
                  isCollapsed: isCollapsed,
                ),
                SidebarAccordion(
                  title: 'User Management',
                  icon: Icons.person_outline_rounded,
                  isExpanded: _userManagementExpanded,
                  onToggle: () => setState(
                    () => _userManagementExpanded = !_userManagementExpanded,
                  ),
                  isCollapsed: isCollapsed,
                  onExpandRequested: () {
                    widget.onExpandRequested?.call();
                    setState(() => _userManagementExpanded = true);
                  },
                  children: [
                    SidebarSubItem(
                      label: 'Student Directory',
                      isSelected: widget.selectedRoute ==
                          DashboardRoute.studentDirectory,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.studentDirectory,
                      ),
                    ),
                    SidebarSubItem(
                      label: 'Staff Accounts',
                      isSelected:
                          widget.selectedRoute == DashboardRoute.staffAccounts,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.staffAccounts,
                      ),
                    ),
                    SidebarSubItem(
                      label: 'RFID Mapping',
                      isSelected:
                          widget.selectedRoute == DashboardRoute.rfidMapping,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.rfidMapping,
                      ),
                    ),
                  ],
                ),
                SidebarAccordion(
                  title: 'System Config',
                  icon: Icons.tune_rounded,
                  isExpanded: _systemConfigExpanded,
                  onToggle: () => setState(
                    () => _systemConfigExpanded = !_systemConfigExpanded,
                  ),
                  isCollapsed: isCollapsed,
                  onExpandRequested: () {
                    widget.onExpandRequested?.call();
                    setState(() => _systemConfigExpanded = true);
                  },
                  children: [
                    SidebarSubItem(
                      label: 'ML & Thresholds',
                      isSelected:
                          widget.selectedRoute == DashboardRoute.mlThresholds,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.mlThresholds,
                      ),
                    ),
                    SidebarSubItem(
                      label: 'Notifications',
                      isSelected:
                          widget.selectedRoute == DashboardRoute.notifications,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.notifications,
                      ),
                    ),
                    SidebarSubItem(
                      label: 'Register Syncs',
                      isSelected:
                          widget.selectedRoute == DashboardRoute.registerSyncs,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.registerSyncs,
                      ),
                    ),
                  ],
                ),
                SidebarNavItem(
                  label: 'Audit & Privacy Logs',
                  icon: Icons.description_outlined,
                  isSelected:
                      widget.selectedRoute == DashboardRoute.auditPrivacyLogs,
                  isStandalone: true,
                  onTap: () => widget.onRouteSelected(
                    DashboardRoute.auditPrivacyLogs,
                  ),
                  isCollapsed: isCollapsed,
                ),
                SidebarNavItem(
                  label: 'Reports & Exports',
                  icon: Icons.bar_chart_outlined,
                  isSelected:
                      widget.selectedRoute == DashboardRoute.reportsExports,
                  isStandalone: true,
                  onTap: () =>
                      widget.onRouteSelected(DashboardRoute.reportsExports),
                  isCollapsed: isCollapsed,
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.sidebarDivider,
          ),
          SidebarFooter(
            name: widget.userName ?? 'Admin User',
            email: widget.userEmail ?? '',
            onSettingsTap: () =>
                widget.onRouteSelected(DashboardRoute.settings),
            onLogoutTap: widget.onLogout ??
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Logout tapped',
                        style: AppTypography.textTheme().bodyMedium?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
            isCollapsed: isCollapsed,
          ),
        ],
      ),
    );
  }
}
