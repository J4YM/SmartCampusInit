import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        EmailListView,
        EmailPopover,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsListView,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ItTechnicianDashboardTab { studentRecords, readerDevices, technicalIssues }

/// "View all notifications"/"View all emails" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of
/// [ItTechnicianDashboardTab]'s own values since it isn't a real,
/// always-visible tab; tapping any real tab clears this back to null.
enum _MailboxView { notifications, email }

abstract final class ItTechnicianColors {
  static const navyBlue = Color(0xFF15253F);
  // Shared brand accent used everywhere else in this app.
  static const azureBlue = Color(0xFF345892);
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF0F5F8);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color rowText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF343A40);
  static Color mutedText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);
  static const dangerRed = Color(0xFFCD4855);
  static const successGreen = Color(0xFF137333);
  // Pale fill for form fields inside this module's dialogs — same token
  // Registrar's own dialog fields use. Sits darker than the card in both
  // themes, same relationship as light mode's fill sitting darker than the
  // white card (mirrors MailboxColors.fieldFill).
  static Color fieldFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF1F5F9);
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
  ItTechnicianDashboardTab _activeTab = ItTechnicianDashboardTab.studentRecords;
  late List<NotificationItemModel> _notifications;

  /// Non-null while "View all notifications"/"View all emails" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;

  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

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

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
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
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            setState(() => _mailboxView = _MailboxView.notifications);
          },
          onMarkAllRead: () {
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
        return EmailPopover(
          emails: const [], // no email backend yet — see EmailPopover doc comment
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            setState(() => _mailboxView = _MailboxView.email);
          },
          onMarkAllRead: () =>
              Navigator.of(popoverContext).pop(), // nothing to mark yet
        );
      },
    );
  }

  /// `ProfileScreen` is pushed onto the app's root `Navigator`, so its
  /// subtree lands outside this page's own local `Theme` (the same
  /// Overlay-escapes-local-Theme issue as the header popovers) — wrap it in
  /// a `Theme` matching the current toggle so its `context.isDarkMode` reads
  /// correctly instead of always seeing the app's ambient theme.
  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: ItTechnicianColors.navyBlue,
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: const ProfileScreen(),
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
              MaterialPageRoute(builder: (_) => _themedProfileScreen()),
            );
          },
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onToggleDarkMode: () {
            _themeMode.value = _themeMode.value == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
            setPopoverState(() {});
          },
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: ItTechnicianColors.navyBlue,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          // A fresh Builder so `context` below is a descendant of the Theme
          // just constructed above (the ValueListenableBuilder's own
          // `context` parameter sits above it in the tree and would still
          // resolve to the app's ambient theme, not this page's toggle).
          child: Builder(
            builder: (context) => _buildScaffold(context),
          ),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
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
          const SchoolLogo(),
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
      onTabSelected: (tab) => setState(() {
        _activeTab = tab;
        _mailboxView = null;
      }),
    );

    final pageContent = DashboardPageWrapper(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 5 : 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          subNavBar,
          const SizedBox(height: 16),
          _buildBody(context),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: ItTechnicianColors.background(context),
      bottomNavigationBar: isMobile
          ? AppBottomNavBar(
              onEmailTap: () => _showEmailMenu(context),
              onNotificationTap: () => _showNotificationsMenu(context),
              onProfileTap: () => _openProfile(context),
              notificationBadgeCount: _notifications.where((n) => !n.isRead).length,
            )
          : null,
      // The whole body is one scrollable column so a short viewport never
      // clips tab content with no way to reach the rest of it.
      body: SingleChildScrollView(child: Column(children: [header, pageContent])),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: _notifications,
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case _MailboxView.email:
        return EmailListView(isDarkMode: _themeMode.value == ThemeMode.dark);
      case null:
        return _buildTabContent(context);
    }
  }

  Widget _buildTabContent(BuildContext context) {
    switch (_activeTab) {
      case ItTechnicianDashboardTab.studentRecords:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetricsRow(stats: widget.initialStats),
            const SizedBox(height: 18),
            widget.studentRecordsTabBuilder(context),
          ],
        );
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

  static const _tabs = [
    (
      ItTechnicianDashboardTab.studentRecords,
      'Student Records',
      Icons.badge_outlined,
    ),
    (
      ItTechnicianDashboardTab.readerDevices,
      'Reader Devices',
      Icons.sensors_outlined,
    ),
    (
      ItTechnicianDashboardTab.technicalIssues,
      'Technical Issues',
      Icons.build_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder(context)),
      ),
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (tab, label, icon) in _tabs) ...[
                _SubNavItem(
                  label: label,
                  icon: icon,
                  isActive: activeTab == tab,
                  onTap: () => onTabSelected(tab),
                ),
                if (tab != _tabs.last.$1) const SizedBox(width: 45),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? ItTechnicianColors.azureBlue : ItTechnicianColors.mutedText(context);
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 3 stat cards that used to be their own "Overview" tab — moved to sit
/// above the Student Records table now that the Overview tab is gone.
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.stats});

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
          return MobileMetricGrid(cards: cards);
        }
        return IntrinsicHeight(
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
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder(context)),
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
                    color: ItTechnicianColors.mutedText(context),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: ItTechnicianColors.mutedText(context)),
        ],
      ),
    );
  }
}
