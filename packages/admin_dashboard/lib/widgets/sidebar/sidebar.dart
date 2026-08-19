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
    this.onLogout,
    this.onBackToHub,
    this.unreadNotificationCount = 0,
    this.onNotificationsTap,
  });

  final DashboardRoute selectedRoute;
  final ValueChanged<DashboardRoute> onRouteSelected;

  /// Falls back to a "Logout tapped" snackbar when not supplied.
  final VoidCallback? onLogout;

  /// Forwarded to [SidebarHeader]'s back-arrow — see its doc comment.
  final VoidCallback? onBackToHub;

  /// Forwarded to [SidebarHeader]'s notification bell — see its doc comment.
  final int unreadNotificationCount;
  final VoidCallback? onNotificationsTap;

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
      child: Container(
        width: AppDimensions.sidebarWidth,
        color: AppColors.sidebarBackground,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SidebarHeader(
                onBackToHub: widget.onBackToHub,
                unreadNotificationCount: widget.unreadNotificationCount,
                onNotificationsTap: widget.onNotificationsTap,
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
                      isSelected:
                          widget.selectedRoute == DashboardRoute.overview,
                      onTap: () =>
                          widget.onRouteSelected(DashboardRoute.overview),
                    ),
                    SidebarAccordion(
                      title: 'User Management',
                      icon: Icons.person_outline_rounded,
                      isExpanded: _userManagementExpanded,
                      onToggle: () => setState(
                        () =>
                            _userManagementExpanded = !_userManagementExpanded,
                      ),
                      children: [
                        SidebarSubItem(
                          label: 'Student Directory',
                          isSelected:
                              widget.selectedRoute ==
                              DashboardRoute.studentDirectory,
                          onTap: () => widget.onRouteSelected(
                            DashboardRoute.studentDirectory,
                          ),
                        ),
                        SidebarSubItem(
                          label: 'Staff Accounts',
                          isSelected:
                              widget.selectedRoute ==
                              DashboardRoute.staffAccounts,
                          onTap: () => widget.onRouteSelected(
                            DashboardRoute.staffAccounts,
                          ),
                        ),
                        SidebarSubItem(
                          label: 'RFID Mapping',
                          isSelected:
                              widget.selectedRoute ==
                              DashboardRoute.rfidMapping,
                          onTap: () => widget.onRouteSelected(
                            DashboardRoute.rfidMapping,
                          ),
                        ),
                      ],
                    ),
                    SidebarAccordion(
                      title: 'System Configuration',
                      icon: Icons.tune_rounded,
                      isExpanded: _systemConfigExpanded,
                      onToggle: () => setState(
                        () => _systemConfigExpanded = !_systemConfigExpanded,
                      ),
                      children: [
                        SidebarSubItem(
                          label: 'ML & Thresholds',
                          isSelected:
                              widget.selectedRoute ==
                              DashboardRoute.mlThresholds,
                          onTap: () => widget.onRouteSelected(
                            DashboardRoute.mlThresholds,
                          ),
                        ),
                        SidebarSubItem(
                          label: 'Notifications',
                          isSelected:
                              widget.selectedRoute ==
                              DashboardRoute.notifications,
                          onTap: () => widget.onRouteSelected(
                            DashboardRoute.notifications,
                          ),
                        ),
                        SidebarSubItem(
                          label: 'Register Syncs',
                          isSelected:
                              widget.selectedRoute ==
                              DashboardRoute.registerSyncs,
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
                          widget.selectedRoute ==
                          DashboardRoute.auditPrivacyLogs,
                      isStandalone: true,
                      onTap: () => widget.onRouteSelected(
                        DashboardRoute.auditPrivacyLogs,
                      ),
                    ),
                    SidebarNavItem(
                      label: 'Reports & Exports',
                      icon: Icons.bar_chart_outlined,
                      isSelected:
                          widget.selectedRoute == DashboardRoute.reportsExports,
                      isStandalone: true,
                      onTap: () =>
                          widget.onRouteSelected(DashboardRoute.reportsExports),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
