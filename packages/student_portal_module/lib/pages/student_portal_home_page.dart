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

import '../data/student_portal_mock_data.dart';
import '../models/attendance_models.dart';
import '../models/good_moral_request_status.dart';
import '../models/schedule_models.dart';
import '../models/student_notification_model.dart';
import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../widgets/day_detail_sheet.dart';
import '../widgets/hero_card.dart';
import '../widgets/month_preview_card.dart';
import '../widgets/my_schedule_card.dart';
import '../widgets/portal_header_bar.dart';
import '../widgets/portal_header_icon_button.dart';
import '../widgets/portal_surface_card.dart';
import '../widgets/section_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/violation_detail_sheet.dart';
import '../widgets/violations_preview_card.dart';
import 'good_moral_request_page.dart';
import 'violations_page.dart';

DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

/// Which full-list view (if any) is swapped in below the header in place of
/// the normal bento dashboard — mirrors every staff dashboard's own
/// `_MailboxView` pattern of swapping body content for "View all" instead
/// of pushing a separate page/route.
enum _MailboxView { notifications, email }

/// Root shell for the student-facing portal — an asymmetric "bento"
/// dashboard (hero snapshot + month calendar beside a Violations &
/// Offenses preview) rather than a tabbed, evenly-gridded admin layout.
///
/// Presentation-only for now (mock data by default via `initialX` params,
/// same fallback convention every other dashboard module in this app
/// follows) — a future connected page in the host app can wire these to
/// Supabase without touching this shell.
class StudentPortalHomePage extends StatefulWidget {
  const StudentPortalHomePage({
    super.key,
    this.studentName = 'Demo Student',
    this.programLine = 'BS Information Technology · 3rd Year · Section A',
    this.onSignOut,
    this.onReturnToHub,
    this.initialSubjects,
    this.initialAttendance,
    this.initialViolations,
    this.initialSchedule,
    this.initialNotifications,
    this.initialGoodMoralRequests,
    this.onSubmitGoodMoralRequest,
  });

  final String studentName;
  final String programLine;
  final VoidCallback? onSignOut;

  /// Set when Admin opens this page from the hub as a preview; renders a
  /// back button in the shared header. Null for a Student's own
  /// direct-login route, where there is no hub to return to.
  final VoidCallback? onReturnToHub;

  final List<SubjectModel>? initialSubjects;
  final List<AttendanceEntry>? initialAttendance;
  final List<StudentViolationModel>? initialViolations;
  final List<StudentScheduleEntryModel>? initialSchedule;
  final List<StudentNotificationModel>? initialNotifications;
  final List<GoodMoralRequestStatus>? initialGoodMoralRequests;

  /// Called with the submitted form values when GoodMoralRequestPage's
  /// "Submit Request" is tapped. Null means demo mode — the page still
  /// opens and closes, nothing is persisted.
  final void Function({
    required String documentType,
    required String purpose,
    String? remarks,
  })? onSubmitGoodMoralRequest;

  @override
  State<StudentPortalHomePage> createState() => _StudentPortalHomePageState();
}

class _StudentPortalHomePageState extends State<StudentPortalHomePage> {
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  late final List<SubjectModel> _subjects =
      widget.initialSubjects ?? StudentPortalMockData.subjects;
  late List<AttendanceEntry> _attendance =
      widget.initialAttendance ?? StudentPortalMockData.generateAttendance();
  late List<StudentViolationModel> _violations =
      widget.initialViolations ?? StudentPortalMockData.violations();
  late List<StudentScheduleEntryModel> _schedule =
      widget.initialSchedule ?? const [];
  late List<StudentNotificationModel> _notifications =
      widget.initialNotifications ?? StudentPortalMockData.notifications();
  late List<GoodMoralRequestStatus> _goodMoralRequests =
      widget.initialGoodMoralRequests ?? const [];

  String? _selectedSubjectId;
  late DateTime _month = _firstOfMonth(DateTime.now());
  DateTime? _selectedDay;

  /// Non-null while the header popover's "View all" swapped the notification
  /// or email list in below the header, in place of the bento dashboard.
  _MailboxView? _mailboxView;

  @override
  void didUpdateWidget(covariant StudentPortalHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `StudentPortalConnectedPage` renders this page before its Supabase
    // fetches complete, so the `initial*` props this page first builds with
    // are mock/empty data — later fetches arrive as a rebuild with new
    // `initial*` props, not a fresh State object. Sync the fields that back
    // a live connected page here so that data actually lands on screen.
    // `_subjects`/`_notifications` are intentionally left alone — a
    // pre-existing, separate concern outside this plan's scope.
    final newAttendance = widget.initialAttendance;
    if (newAttendance != null && newAttendance != oldWidget.initialAttendance) {
      _attendance = newAttendance;
    }
    final newViolations = widget.initialViolations;
    if (newViolations != null && newViolations != oldWidget.initialViolations) {
      _violations = newViolations;
    }
    final newSchedule = widget.initialSchedule;
    if (newSchedule != null && newSchedule != oldWidget.initialSchedule) {
      _schedule = newSchedule;
    }
    final newGoodMoralRequests = widget.initialGoodMoralRequests;
    if (newGoodMoralRequests != null &&
        newGoodMoralRequests != oldWidget.initialGoodMoralRequests) {
      _goodMoralRequests = newGoodMoralRequests;
    }
  }

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  List<AttendanceEntry> get _subjectFilteredEntries {
    if (_selectedSubjectId == null) return _attendance;
    return _attendance.where((e) => e.subjectId == _selectedSubjectId).toList();
  }

  Map<DateTime, List<AttendanceEntry>> get _monthEntriesByDay {
    final map = <DateTime, List<AttendanceEntry>>{};
    for (final entry in _subjectFilteredEntries) {
      final day = dateOnly(entry.date);
      if (day.year == _month.year && day.month == _month.month) {
        (map[day] ??= []).add(entry);
      }
    }
    return map;
  }

  /// The earliest month any attendance data exists for — bounds the "prev
  /// month" arrow so a student can't page back into an empty void.
  DateTime get _earliestMonth {
    if (_attendance.isEmpty) return _firstOfMonth(DateTime.now());
    final earliest =
        _attendance.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    return _firstOfMonth(earliest);
  }

  DateTime get _latestMonth => _firstOfMonth(DateTime.now());

  bool get _canGoPreviousMonth => _month.isAfter(_earliestMonth);
  bool get _canGoNextMonth => _month.isBefore(_latestMonth);

  /// This month's stats for the hero ring — always across every subject,
  /// independent of the month card's own subject filter.
  ({double rate, int present, int late, int absent}) get _monthStats {
    final now = DateTime.now();
    final month = _attendance
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .toList();
    final present =
        month.where((e) => e.status == AttendanceStatus.present).length;
    final late = month.where((e) => e.status == AttendanceStatus.late).length;
    final absent =
        month.where((e) => e.status == AttendanceStatus.absent).length;
    final rate = month.isEmpty ? 0.0 : present / month.length;
    return (rate: rate, present: present, late: late, absent: absent);
  }

  void _changeMonth(int deltaMonths) {
    setState(() {
      _month = DateTime(_month.year, _month.month + deltaMonths);
      _selectedDay = null;
    });
  }

  void _openDay(DateTime day) {
    setState(() => _selectedDay = day);
    final entries = _monthEntriesByDay[day] ?? const <AttendanceEntry>[];
    // isDarkMode is read from _themeMode directly, not context — see
    // showDayDetailSheet's own doc comment for why this State's bare
    // `context` can't be trusted for that here.
    showDayDetailSheet(
      context,
      day,
      entries,
      isDarkMode: _themeMode.value == ThemeMode.dark,
    ).then((_) => mounted ? setState(() => _selectedDay = null) : null);
  }

  void _openViolation(StudentViolationModel violation) {
    showViolationDetailSheet(
      context,
      violation,
      isDarkMode: _themeMode.value == ThemeMode.dark,
    );
  }

  // Both pages below are pushed on the app's root Navigator, so — like the
  // header popovers above — they land outside this page's own local Theme
  // and need their own explicit re-wrap for context.isDarkMode to resolve
  // to the portal's actual toggle instead of the app's ambient theme.
  ThemeData _pushedPageTheme() => ThemeData(
        useMaterial3: true,
        brightness:
            _themeMode.value == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );

  void _openViolationsPage() {
    final theme = _pushedPageTheme();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: ViolationsPage(violations: _violations),
        ),
      ),
    );
  }

  void _openGoodMoralRequestPage() {
    final theme = _pushedPageTheme();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: GoodMoralRequestPage(
            onSubmit: ({required documentType, required purpose, remarks}) {
              widget.onSubmitGoodMoralRequest?.call(
                documentType: documentType,
                purpose: purpose,
                remarks: remarks,
              );
            },
          ),
        ),
      ),
    );
  }

  List<NotificationItemModel> get _notificationItems => [
        for (final n in _notifications)
          NotificationItemModel(
            id: n.id,
            title: n.title,
            message: n.message,
            timestamp: n.timestamp,
            isRead: n.isRead,
          ),
      ];

  void _markAllNotificationsRead() {
    setState(() {
      _notifications = [
        for (final n in _notifications) n.copyWith(isRead: true),
      ];
    });
  }

  void _showNotificationsListView() {
    setState(() => _mailboxView = _MailboxView.notifications);
  }

  void _showEmailListView() {
    setState(() => _mailboxView = _MailboxView.email);
  }

  void _closeMailboxView() {
    setState(() => _mailboxView = null);
  }

  /// Clicking the header logo acts as a "home" link — dismisses "View all
  /// notifications/email" and returns to the main bento dashboard, the same
  /// destination every other dashboard's logo resets to.
  void _goHome() => _closeMailboxView();

  /// Header bell — the notification tab. Same component, same behavior as
  /// every staff dashboard's `NotificationsPopover`: an unfiltered glance
  /// at every notification, "Mark all as read" bulk-marks the whole list,
  /// and "View all notifications" opens the matching full-list page.
  void _showNotificationsMenu() {
    final isDark = _themeMode.value == ThemeMode.dark;
    showHeaderPopover(
      context: context,
      centered: context.isMobileWidth,
      cardWidth: 400,
      contentBuilder: (popoverContext, setPopoverState) {
        // showHeaderPopover's route renders through the root Overlay, which
        // sits outside this page's own local Theme (see brightness_x.dart)
        // — re-wrap so `context.isDarkMode` inside the popover's content
        // resolves to the page's actual toggle instead of the app's
        // ambient (always-light) theme.
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
          child: Builder(
            builder: (themedContext) => NotificationsPopover(
              notifications: _notificationItems,
              // Use themedContext (inside the Theme just above), not the
              // outer context — same reasoning as showDayDetailSheet's own
              // doc comment: this State's bare context can't be trusted for
              // brightness-dependent colors.
              accentColor: StudentPortalColors.accent(themedContext),
              isDarkMode: isDark,
              onViewAll: () {
                Navigator.of(popoverContext).pop();
                _showNotificationsListView();
              },
              onMarkAllRead: () {
                Navigator.of(popoverContext).pop();
                _markAllNotificationsRead();
              },
            ),
          ),
        );
      },
    );
  }

  /// Header mail icon — the email tab. Same component, same behavior as
  /// every staff dashboard's `EmailPopover`. No email inbox exists
  /// anywhere in this app yet (see `EmailPopover`'s doc comment), so this
  /// renders the same permanent "No Email" empty state every other
  /// module's mail icon shows.
  void _showEmailMenu() {
    final isDark = _themeMode.value == ThemeMode.dark;
    showHeaderPopover(
      context: context,
      centered: context.isMobileWidth,
      cardWidth: 400,
      contentBuilder: (popoverContext, setPopoverState) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
          child: Builder(
            builder: (themedContext) => EmailPopover(
              emails: const [],
              isDarkMode: isDark,
              onViewAll: () {
                Navigator.of(popoverContext).pop();
                _showEmailListView();
              },
              onMarkAllRead: () => Navigator.of(popoverContext).pop(),
            ),
          ),
        );
      },
    );
  }

  /// `ProfileScreen` is pushed onto the app's root `Navigator`, so its
  /// subtree lands outside this page's own local `Theme` — the same
  /// Overlay/route-escapes-local-Theme issue every dashboard's header
  /// popovers already work around. Wrap it in a `Theme` matching the
  /// current toggle so its `context.isDarkMode` reads correctly instead of
  /// always seeing the app's ambient theme.
  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: StudentPortalColors.brandPrimary,
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: const ProfileScreen(),
    );
  }

  /// Shared "Are you sure you want to logout?" confirmation, matching every
  /// staff dashboard's own `_confirmLogout` — every Sign Out trigger below
  /// (both header icons and the account dropdown's Log Out row) goes
  /// through this instead of calling `widget.onSignOut` directly.
  void _confirmLogout() {
    final isDark = _themeMode.value == ThemeMode.dark;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          isDarkMode: isDark,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  /// Header avatar — "Profile Settings / Dark Mode / Sign Out", the same
  /// [AccountProfileMenu] every staff dashboard's header avatar opens (see
  /// its own doc comment). Dark mode used to be its own standalone header
  /// icon here; it now lives only in this dropdown, matching every other
  /// dashboard's convention of one combined account menu instead of a
  /// separate toggle.
  void _openProfile() {
    showHeaderPopover(
      context: context,
      // The profile trigger now lives in AppBottomNavBar on mobile (see
      // build()), not the header — anchor just above it instead of
      // centering on screen, same as every other dashboard's own
      // _openProfile now that they all made the same bottom-nav move.
      anchorAboveBottomNav: context.isMobileWidth,
      cardWidth: 260,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          userName: widget.studentName,
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
            _confirmLogout();
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
          data: Theme.of(context).copyWith(
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          child: Builder(
            builder: (context) {
              final unreadNotificationsCount =
                  _notifications.where((n) => !n.isRead).length;
              final stats = _monthStats;
              final compact = context.isMobileWidth;

              final heroCard = HeroCard(
                studentName: widget.studentName,
                programLine: widget.programLine,
                attendanceRate: stats.rate,
                presentCount: stats.present,
                lateCount: stats.late,
                absentCount: stats.absent,
              );

              final monthCard = MonthPreviewCard(
                subjects: _subjects,
                selectedSubjectId: _selectedSubjectId,
                onSubjectChanged: (id) => setState(() {
                  _selectedSubjectId = id;
                  _selectedDay = null;
                }),
                month: _month,
                entriesByDay: _monthEntriesByDay,
                selectedDay: _selectedDay,
                onDaySelected: _openDay,
                onPreviousMonth:
                    _canGoPreviousMonth ? () => _changeMonth(-1) : null,
                onNextMonth: _canGoNextMonth ? () => _changeMonth(1) : null,
              );

              final violationsCard = ViolationsPreviewCard(
                violations: _violations,
                onSeeAll: _openViolationsPage,
                onOpenViolation: _openViolation,
              );

              final scheduleCard = MyScheduleCard(entries: _schedule);

              final goodMoralCard = PortalSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'My Document Requests'),
                    if (_goodMoralRequests.isEmpty)
                      Text(
                        'No document requests yet.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: StudentPortalColors.textSecondary(context),
                        ),
                      )
                    else
                      for (final request in _goodMoralRequests)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${request.documentType} — ${request.purpose}',
                                  style: GoogleFonts.inter(fontSize: 13),
                                ),
                              ),
                              StatusBadge(
                                label: request.status,
                                foreground: request.isFulfilled
                                    ? StudentPortalColors.presentFg(context)
                                    : StudentPortalColors.pendingFg(context),
                                background: request.isFulfilled
                                    ? StudentPortalColors.presentBg(context)
                                    : StudentPortalColors.pendingBg(context),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              );

              // Same shape/cap/action-icon convention as every staff
              // dashboard's `AppHeaderNavBar` — fixed navy background, same
              // shared `HeaderIconButton`/`ProfileAvatarButton` chrome.
              final header = PortalHeaderBar(
                title: 'Student Portal',
                subtitle: 'Mission Control',
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onReturnToHub != null) ...[
                      HeaderIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back to Hub',
                        onTap: widget.onReturnToHub!,
                      ),
                      const SizedBox(width: 12),
                    ],
                    SchoolLogo(onTap: _goHome),
                  ],
                ),
                // Mail/notification/profile move into the bottom nav bar on
                // mobile — same convention every other dashboard (Registrar,
                // Professor, Guidance Counselor, …) uses: the compact header
                // keeps only sign-out, everything else is reachable via
                // AppBottomNavBar (Scaffold.bottomNavigationBar) instead.
                actions: [
                  if (!compact) ...[
                    HeaderIconButton(
                      icon: Icons.mail_outline_rounded,
                      tooltip: 'Email',
                      onTap: _showEmailMenu,
                    ),
                    HeaderIconButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      badgeCount: unreadNotificationsCount,
                      onTap: _showNotificationsMenu,
                    ),
                    HeaderIconButton(
                      icon: Icons.description_outlined,
                      tooltip: 'Good Moral Request',
                      onTap: _openGoodMoralRequestPage,
                    ),
                    const SizedBox(width: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProfileAvatarButton(onTap: _openProfile),
                        if (widget.onSignOut != null) ...[
                          const SizedBox(width: 10),
                          HeaderIconButton(
                            icon: Icons.logout_rounded,
                            tooltip: 'Sign Out',
                            onTap: _confirmLogout,
                          ),
                        ],
                      ],
                    ),
                  ] else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HeaderIconButton(
                          icon: Icons.description_outlined,
                          tooltip: 'Good Moral Request',
                          onTap: _openGoodMoralRequestPage,
                        ),
                        if (widget.onSignOut != null) ...[
                          const SizedBox(width: 10),
                          HeaderIconButton(
                            icon: Icons.logout_rounded,
                            tooltip: 'Sign Out',
                            onTap: _confirmLogout,
                          ),
                        ],
                      ],
                    ),
                ],
              );

              final bentoContent = compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heroCard,
                        const SizedBox(height: StudentPortalSpacing.lg),
                        monthCard,
                        const SizedBox(height: StudentPortalSpacing.lg),
                        violationsCard,
                        const SizedBox(height: StudentPortalSpacing.lg),
                        scheduleCard,
                        const SizedBox(height: StudentPortalSpacing.lg),
                        goodMoralCard,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              heroCard,
                              const SizedBox(height: StudentPortalSpacing.lg),
                              monthCard,
                            ],
                          ),
                        ),
                        const SizedBox(width: StudentPortalSpacing.lg),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              violationsCard,
                              const SizedBox(height: StudentPortalSpacing.lg),
                              scheduleCard,
                              const SizedBox(height: StudentPortalSpacing.lg),
                              goodMoralCard,
                            ],
                          ),
                        ),
                      ],
                    );

              final mailboxView = _mailboxView;
              final mainContent = mailboxView == null
                  ? bentoContent
                  : _MailboxContent(
                      view: mailboxView,
                      notifications: _notificationItems,
                      isDarkMode: mode == ThemeMode.dark,
                      onBack: _closeMailboxView,
                    );

              return Scaffold(
                backgroundColor: StudentPortalColors.pageBackground(context),
                bottomNavigationBar: compact
                    ? AppBottomNavBar(
                        onEmailTap: _showEmailMenu,
                        onNotificationTap: _showNotificationsMenu,
                        onProfileTap: _openProfile,
                        notificationBadgeCount: unreadNotificationsCount,
                        isDarkMode: mode == ThemeMode.dark,
                      )
                    : null,
                // The header stays fixed at the top; only the content below
                // it scrolls.
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: SingleChildScrollView(
                        child: DashboardPageWrapper(
                          maxWidth: StudentPortalSpacing.maxContentWidth,
                          padding: EdgeInsets.fromLTRB(
                            StudentPortalSpacing.pageHorizontal(context),
                            StudentPortalSpacing.lg,
                            StudentPortalSpacing.pageHorizontal(context),
                            StudentPortalSpacing.xxl,
                          ),
                          child: mainContent,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Swapped in below the header in place of the bento dashboard when a
/// header popover's "View all" is tapped — a back row above the same
/// shared `NotificationsListView`/`EmailListView` every staff dashboard's
/// own "View all" swaps into its body, rather than pushing a separate
/// page/route. The list view itself already carries a "Notifications"/
/// "Email" title, so this only adds the way back to the dashboard.
class _MailboxContent extends StatelessWidget {
  const _MailboxContent({
    required this.view,
    required this.notifications,
    required this.isDarkMode,
    required this.onBack,
  });

  final _MailboxView view;
  final List<NotificationItemModel> notifications;
  final bool isDarkMode;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PortalHeaderIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: onBack,
            ),
            const SizedBox(width: StudentPortalSpacing.md),
            Text(
              'Back to Dashboard',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: StudentPortalColors.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: StudentPortalSpacing.lg),
        switch (view) {
          _MailboxView.notifications => NotificationsListView(
              notifications: notifications,
              isDarkMode: isDarkMode,
            ),
          _MailboxView.email => EmailListView(isDarkMode: isDarkMode),
        },
      ],
    );
  }
}
