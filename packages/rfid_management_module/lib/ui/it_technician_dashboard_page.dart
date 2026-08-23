import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        EmailPopover,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ItTechnicianDashboardTab { overview, studentRecords, readerDevices, technicalIssues }

abstract final class ItTechnicianColors {
  static const navyBlue = Color(0xFF15253F);
  static const azureBlue = Color(0xFF2563EB);
  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE5E7EB);
  static const rowText = Color(0xFF111827);
  static const mutedText = Color(0xFF6B7280);
}

class ItTechnicianOverviewStats {
  const ItTechnicianOverviewStats({
    required this.totalStudents,
    required this.totalReaders,
    required this.onlineReaders,
    required this.openTicketCount,
  });

  final int totalStudents;
  final int totalReaders;
  final int onlineReaders;
  final int openTicketCount;
}

class ItTechnicianDashboardPage extends StatefulWidget {
  const ItTechnicianDashboardPage({
    super.key,
    this.technicianName = 'IT Technician',
    this.onReturnToHub,
    this.onSignOut,
    this.initialStats,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    required this.studentRecordsTabBuilder,
    required this.readerDevicesTabBuilder,
    required this.technicalIssuesTabBuilder,
    this.onReportIssue,
  });

  final String technicianName;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;
  final ItTechnicianOverviewStats? initialStats;
  final List<NotificationItemModel>? initialNotifications;
  final Future<void> Function()? onMarkNotificationsRead;

  final WidgetBuilder studentRecordsTabBuilder;
  final WidgetBuilder readerDevicesTabBuilder;
  final WidgetBuilder technicalIssuesTabBuilder;

  /// Unused by this shell directly (IT Technician doesn't file reports on
  /// itself) — kept for constructor symmetry with the Teacher/Admin entry
  /// points added in later tasks; always null from this page today.
  final VoidCallback? onReportIssue;

  @override
  State<ItTechnicianDashboardPage> createState() => _ItTechnicianDashboardPageState();
}

class _ItTechnicianDashboardPageState extends State<ItTechnicianDashboardPage> {
  ItTechnicianDashboardTab _activeTab = ItTechnicianDashboardTab.overview;
  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = List.of(widget.initialNotifications ?? const []);
  }

  @override
  void didUpdateWidget(covariant ItTechnicianDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fresh = widget.initialNotifications;
    if (fresh != null && !identical(fresh, oldWidget.initialNotifications)) {
      setState(() => _notifications = List.of(fresh));
    }
  }

  Future<void> _markNotificationsRead() async {
    if (_notifications.every((n) => n.isRead)) return;
    setState(() {
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  void _showNotificationsMenu(BuildContext context) {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: _notifications,
          accentColor: ItTechnicianColors.azureBlue,
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
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return EmailPopover(onViewAll: () => Navigator.of(popoverContext).pop());
      },
    );
  }

  void _openProfile(BuildContext context) {
    showHeaderPopover(
      context: context,
      cardWidth: 260,
      anchorAboveBottomNav: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          onViewProfile: () {
            Navigator.of(popoverContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          isDarkMode: false,
          onToggleDarkMode: () {},
          onLogout: () {
            Navigator.of(popoverContext).pop();
            _confirmLogout(context);
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
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobileWidth;

    final header = AppHeaderNavBar(
      title: 'IT Technician Dashboard',
      subtitle: 'Devices, RFID, and technical support',
      backgroundColor: ItTechnicianColors.navyBlue,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onReturnToHub != null) ...[
            HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: widget.onReturnToHub!),
            const SizedBox(width: 12),
          ],
          Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              'STI',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 12 : 14,
                fontWeight: FontWeight.w800,
                color: ItTechnicianColors.navyBlue,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (!isMobile) ...[
          HeaderIconButton(icon: Icons.mail_outline_rounded, onTap: () => _showEmailMenu(context)),
          HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            badgeCount: _notifications.where((n) => !n.isRead).length,
            onTap: () => _showNotificationsMenu(context),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.technicianName,
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(width: 15),
              ProfileAvatarButton(onTap: () => _openProfile(context)),
              if (widget.onSignOut != null) ...[
                const SizedBox(width: 10),
                HeaderIconButton(icon: Icons.logout_rounded, onTap: widget.onSignOut!),
              ],
            ],
          ),
        ] else if (widget.onSignOut != null)
          HeaderIconButton(icon: Icons.logout_rounded, onTap: widget.onSignOut!),
      ],
    );

    final subNavBar = _SubNavBar(
      activeTab: _activeTab,
      onTabSelected: (tab) => setState(() => _activeTab = tab),
    );

    // On mobile, `pageContent` sits inside the body's outer
    // SingleChildScrollView (see `body:` below), which gives unbounded
    // height — an Expanded child there throws a RenderFlex layout error.
    // On desktop, `pageContent` itself is the Expanded child of the outer
    // Column, so it does have bounded height and the tab content can
    // expand to fill it. Same split as professor_dashboard_page.dart's
    // pageContent builder.
    final pageContent = DashboardPageWrapper(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 5 : 24, vertical: 16),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                subNavBar,
                const SizedBox(height: 16),
                _buildTabContent(context),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                subNavBar,
                const SizedBox(height: 16),
                Expanded(child: _buildTabContent(context)),
              ],
            ),
    );

    return Scaffold(
      backgroundColor: ItTechnicianColors.background,
      bottomNavigationBar: isMobile
          ? AppBottomNavBar(
              onEmailTap: () => _showEmailMenu(context),
              onNotificationTap: () => _showNotificationsMenu(context),
              onProfileTap: () => _openProfile(context),
              notificationBadgeCount: _notifications.where((n) => !n.isRead).length,
            )
          : null,
      body: isMobile
          ? SingleChildScrollView(child: Column(children: [header, pageContent]))
          : Column(children: [header, Expanded(child: pageContent)]),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    switch (_activeTab) {
      case ItTechnicianDashboardTab.overview:
        return _OverviewTab(stats: widget.initialStats);
      case ItTechnicianDashboardTab.studentRecords:
        return widget.studentRecordsTabBuilder(context);
      case ItTechnicianDashboardTab.readerDevices:
        return widget.readerDevicesTabBuilder(context);
      case ItTechnicianDashboardTab.technicalIssues:
        return widget.technicalIssuesTabBuilder(context);
    }
  }
}

class _SubNavBar extends StatelessWidget {
  const _SubNavBar({required this.activeTab, required this.onTabSelected});

  final ItTechnicianDashboardTab activeTab;
  final ValueChanged<ItTechnicianDashboardTab> onTabSelected;

  static const _labels = {
    ItTechnicianDashboardTab.overview: 'Overview',
    ItTechnicianDashboardTab.studentRecords: 'Student Records',
    ItTechnicianDashboardTab.readerDevices: 'Reader Devices',
    ItTechnicianDashboardTab.technicalIssues: 'Technical Issues',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ItTechnicianColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder),
      ),
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in ItTechnicianDashboardTab.values) ...[
                _SubNavItem(
                  label: _labels[tab]!,
                  isActive: activeTab == tab,
                  onTap: () => onTabSelected(tab),
                ),
                if (tab != ItTechnicianDashboardTab.values.last) const SizedBox(width: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: isActive ? ItTechnicianColors.azureBlue : Colors.transparent,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w600,
            color: isActive ? ItTechnicianColors.azureBlue : ItTechnicianColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.stats});

  final ItTechnicianOverviewStats? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats ??
        const ItTechnicianOverviewStats(
          totalStudents: 0,
          totalReaders: 0,
          onlineReaders: 0,
          openTicketCount: 0,
        );

    final cards = [
      _StatCard(label: 'Total Students', value: '${s.totalStudents}', icon: Icons.school_outlined),
      _StatCard(
        label: 'Readers Online',
        value: '${s.onlineReaders}/${s.totalReaders}',
        icon: Icons.sensors,
      ),
      _StatCard(label: 'Open Technical Issues', value: '${s.openTicketCount}', icon: Icons.build_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return SingleChildScrollView(child: MobileMetricGrid(cards: cards));
        }
        // Explicit bounded height (matching _StatCard's own fixed height)
        // rather than relying on an ambient bounded-height parent — this
        // tab can be laid out with an unbounded height (mobile's outer
        // SingleChildScrollView), where CrossAxisAlignment.stretch on a
        // plain Row would throw. Same fix as professor_dashboard_page.dart's
        // equivalent stat-card row.
        return SizedBox(
          height: 124,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 124,
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.mutedText,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: ItTechnicianColors.mutedText),
        ],
      ),
    );
  }
}
