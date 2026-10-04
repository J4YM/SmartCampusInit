import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsListView,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/parent_portal_mock_data.dart';
import '../models/attendance_models.dart';
import '../models/good_moral_request_status.dart';
import '../models/intervention_models.dart';
import '../models/schedule_models.dart';
import '../models/student_notification_model.dart';
import '../models/violation_models.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import '../widgets/day_detail_sheet.dart';
import '../widgets/intervention_detail_sheet.dart';
import '../widgets/portal_header_bar.dart';
import '../widgets/portal_header_icon_button.dart';
import '../widgets/violation_detail_sheet.dart';
import '../widgets/month_preview_card.dart';
import '../widgets/parent_overview_widgets.dart';
import 'good_moral_request_page.dart';
import 'interventions_page.dart';
import 'violations_page.dart';

/// Which full-list view (if any) is swapped in below the header in place of
/// the normal bento dashboard — mirrors every staff dashboard's own
/// `_MailboxView` pattern of swapping body content for "View all" instead
/// of pushing a separate page/route.
enum _MailboxView { notifications }

/// Root shell for the Parent Portal. Unlike the Student Portal (a student's
/// own ring + month calendar), it is laid out for a parent checking in on
/// their child: a greeting + child profile, today's status, a "needs your
/// attention" list, this month at a glance, attendance by week, conduct,
/// the class schedule and document requests — in plain language.
///
/// Presentation-only for now (mock data by default via `initialX` params,
/// same fallback convention every other dashboard module in this app
/// follows) — a future connected page in the host app can wire these to
/// Supabase without touching this shell.
class ParentPortalHomePage extends StatefulWidget {
  const ParentPortalHomePage({
    super.key,
    this.studentName = 'Juan Dela Cruz',
    this.programLine = 'BS Information Technology · 3rd Year · BSIT-3A',
    this.parentName = 'Demo Parent',
    this.studentNumber,
    this.onSignOut,
    this.onReturnToHub,
    this.initialSubjects,
    this.initialAttendance,
    this.initialViolations,
    this.initialSchedule,
    this.initialNotifications,
    this.initialGoodMoralRequests,
    this.initialInterventions,
    this.onInterventionRead,
    this.onSubmitGoodMoralRequest,
  });

  /// The linked child's full name.
  final String studentName;

  /// The child's program / year / section line.
  final String programLine;

  /// The signed-in parent's own name — greeted at the top and shown in the
  /// account menu.
  final String parentName;

  final String? studentNumber;
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

  /// Intervention messages from the school about the child. Null falls back
  /// to demo messages.
  final List<InterventionMessageModel>? initialInterventions;

  /// Called with a message id once the parent opens it (to persist "read").
  final void Function(String id)? onInterventionRead;

  /// Called with the submitted form values when GoodMoralRequestPage's
  /// "Submit Request" is tapped. Null means demo mode — the page still
  /// opens and closes, nothing is persisted.
  final void Function({
    required String documentType,
    required String purpose,
    String? remarks,
  })? onSubmitGoodMoralRequest;

  @override
  State<ParentPortalHomePage> createState() => _ParentPortalHomePageState();
}

class _ParentPortalHomePageState extends State<ParentPortalHomePage> {
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  late List<AttendanceEntry> _attendance =
      widget.initialAttendance ?? ParentPortalMockData.generateAttendance();
  late List<StudentViolationModel> _violations =
      widget.initialViolations ?? ParentPortalMockData.violations();
  late List<StudentScheduleEntryModel> _schedule =
      widget.initialSchedule ?? ParentPortalMockData.schedule();
  late List<StudentNotificationModel> _notifications =
      widget.initialNotifications ?? ParentPortalMockData.notifications();
  late List<GoodMoralRequestStatus> _goodMoralRequests =
      widget.initialGoodMoralRequests ?? const [];
  late List<InterventionMessageModel> _interventions =
      widget.initialInterventions ?? ParentPortalMockData.interventions();

  /// Non-null while the header popover's "View all" swapped the notification
  /// list in below the header, in place of the bento dashboard.
  _MailboxView? _mailboxView;

  @override
  void didUpdateWidget(covariant ParentPortalHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `ParentPortalConnectedPage` renders this page before its Supabase
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
    final newInterventions = widget.initialInterventions;
    if (newInterventions != null &&
        newInterventions != oldWidget.initialInterventions) {
      _interventions = newInterventions;
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

  // --- Calendar state --------------------------------------------------

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  Map<DateTime, List<AttendanceEntry>> get _monthEntriesByDay {
    final map = <DateTime, List<AttendanceEntry>>{};
    for (final entry in _attendance) {
      final day = dateOnly(entry.date);
      if (day.year == _month.year && day.month == _month.month) {
        (map[day] ??= []).add(entry);
      }
    }
    return map;
  }

  /// The earliest month any attendance exists for — bounds the "previous
  /// month" arrow so a parent can't page back into an empty void.
  DateTime get _earliestMonth {
    final now = DateTime.now();
    if (_attendance.isEmpty) return DateTime(now.year, now.month);
    final earliest =
        _attendance.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    return DateTime(earliest.year, earliest.month);
  }

  DateTime get _latestMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  bool get _canGoPreviousMonth => _month.isAfter(_earliestMonth);
  bool get _canGoNextMonth => _month.isBefore(_latestMonth);

  void _changeMonth(int deltaMonths) {
    setState(() {
      _month = DateTime(_month.year, _month.month + deltaMonths);
      _selectedDay = null;
    });
  }

  /// "View all" on the Today card: the child's complete weekly schedule.
  /// Reads the theme toggle directly — this State's own `context` sits above
  /// the local Theme (see showDayDetailSheet's doc comment).
  void _openFullSchedule() {
    final isDark = _themeMode.value == ThemeMode.dark;
    final theme = ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).withPoppins();
    showResponsiveSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF191A1F) : Colors.white,
      desktopMaxWidth: 560,
      builder: (sheetContext) => Theme(
        data: theme,
        child: Builder(
          builder: (themedContext) => SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(themedContext).height * 0.85,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Class schedule',
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color:
                                  ParentPortalColors.textPrimary(themedContext),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Close',
                          child: InkWell(
                            onTap: () => Navigator.of(sheetContext).pop(),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 22,
                                color: ParentPortalColors.textSecondary(
                                    themedContext),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    WeeklyScheduleCard(entries: _schedule, embedded: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Interventions -----------------------------------------------------

  void _markInterventionRead(String id) {
    final current = _interventions.where((m) => m.id == id);
    if (current.isEmpty || current.first.isRead) return;
    setState(() {
      _interventions = [
        for (final m in _interventions)
          m.id == id ? m.copyWith(isRead: true) : m,
      ];
    });
    widget.onInterventionRead?.call(id);
  }

  /// Tapping a message on the card marks it read and opens just that
  /// message in a detail popup. Reads the theme toggle directly (see
  /// _openFullSchedule).
  void _openIntervention(InterventionMessageModel message) {
    _markInterventionRead(message.id);
    showInterventionDetailSheet(
      context,
      message,
      isDarkMode: _themeMode.value == ThemeMode.dark,
    );
  }

  /// "View all" on the Interventions card: the full list page, like the
  /// Violations page.
  void _openInterventionsPage(
      [InterventionFilter filter = InterventionFilter.all]) {
    final theme = _pushedPageTheme();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: InterventionsPage(
            messages: _interventions,
            initialFilter: filter,
            onRead: _markInterventionRead,
          ),
        ),
      ),
    );
  }

  void _openDay(DateTime day) {
    setState(() => _selectedDay = day);
    final entries = [
      for (final e in _attendance)
        if (dateOnly(e.date) == day) e,
    ];
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
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ).withPoppins();

  void _openViolationsPage([ViolationFilter filter = ViolationFilter.all]) {
    final theme = _pushedPageTheme();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: ViolationsPage(violations: _violations, initialFilter: filter),
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

  void _closeMailboxView() {
    setState(() => _mailboxView = null);
  }

  /// Clicking the header logo acts as a "home" link — dismisses "View all
  /// notifications" and returns to the main bento dashboard, the same
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
          ).withPoppins(),
          child: Builder(
            builder: (themedContext) => NotificationsPopover(
              notifications: _notificationItems,
              // Use themedContext (inside the Theme just above), not the
              // outer context — same reasoning as showDayDetailSheet's own
              // doc comment: this State's bare context can't be trusted for
              // brightness-dependent colors.
              accentColor: ParentPortalColors.accent(themedContext),
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
        colorSchemeSeed: ParentPortalColors.brandPrimary,
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ).withPoppins(),
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
          userName: widget.parentName,
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
              final compact = context.isMobileWidth;

              final childFirst =
                  widget.studentName.trim().split(RegExp(r'\s+')).first;
              final statusByDay = dailyStatuses(_attendance);
              final today = dateOnly(DateTime.now());
              final todaysClasses = [
                for (final e in _schedule)
                  if (scheduleWeekdays(e).contains(today.weekday)) e,
              ];

              final banner = ChildProfileBanner(
                parentName: widget.parentName,
                childName: widget.studentName,
                programLine: widget.programLine,
                studentNumber: widget.studentNumber,
              );
              final todayCard = TodayStatusCard(
                childFirstName: childFirst,
                todayStatus: statusByDay[today],
                todaysClasses: todaysClasses,
                onViewAll: _openFullSchedule,
              );
              final summaryCard =
                  AttendanceSummaryCard(statusByDay: statusByDay);
              final calendarCard = MonthPreviewCard(
                // Attendance is recorded per day, so there is no subject
                // filter on this calendar.
                subjects: const [],
                selectedSubjectId: null,
                onSubjectChanged: (_) {},
                month: _month,
                entriesByDay: _monthEntriesByDay,
                selectedDay: _selectedDay,
                onDaySelected: _openDay,
                onPreviousMonth:
                    _canGoPreviousMonth ? () => _changeMonth(-1) : null,
                onNextMonth: _canGoNextMonth ? () => _changeMonth(1) : null,
              );
              final interventionsCard = InterventionsCard(
                messages: _interventions,
                onSeeAll: _openInterventionsPage,
                onOpenFiltered: _openInterventionsPage,
                onOpenMessage: _openIntervention,
              );
              final disciplineCard = DisciplineSummaryCard(
                violations: _violations,
                onSeeAll: _openViolationsPage,
                onOpenFiltered: _openViolationsPage,
                onOpenViolation: _openViolation,
              );
              final documentsCard = DocumentRequestsCard(
                requests: _goodMoralRequests,
                onRequest: _openGoodMoralRequestPage,
              );

              // Same shape/cap/action-icon convention as every staff
              // dashboard's `AppHeaderNavBar` — fixed navy background, same
              // shared `HeaderIconButton`/`ProfileAvatarButton` chrome.
              final header = PortalHeaderBar(
                title: 'Parent Portal',
                subtitle: kSchoolName,
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
                // keeps no action icons — notifications and profile are
                // reachable via AppBottomNavBar (Scaffold.bottomNavigationBar)
                // instead, and the document request button lives in the
                // document requests card. Sign-out lives only in the profile dropdown now,
                // not as a standalone header icon.
                actions: [
                  if (!compact) ...[
                    HeaderIconButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      badgeCount: unreadNotificationsCount,
                      onTap: _showNotificationsMenu,
                    ),
                    const SizedBox(width: 4),
                    ProfileAvatarButton(onTap: _openProfile),
                  ],
                ],
              );

              // Parent-first order: who and how is my child today, then the
              // attendance calendar and the records behind it.
              const gap = SizedBox(height: ParentPortalSpacing.lg);
              final bentoContent = compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        banner,
                        gap,
                        todayCard,
                        gap,
                        summaryCard,
                        gap,
                        calendarCard,
                        gap,
                        interventionsCard,
                        gap,
                        disciplineCard,
                        gap,
                        documentsCard,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        banner,
                        gap,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Today and This-month-at-a-glance sit side
                                  // by side at the same height. The count
                                  // tiles' per-row choice is made here, from
                                  // the width this row gets, because an
                                  // IntrinsicHeight can't measure a
                                  // LayoutBuilder inside the card.
                                  LayoutBuilder(
                                    builder: (context, c) {
                                      const lg = ParentPortalSpacing.lg;
                                      // Card width less its padding and border.
                                      final inner = (c.maxWidth - lg) / 2 -
                                          2 * lg -
                                          2;
                                      return IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(child: todayCard),
                                            const SizedBox(width: lg),
                                            Expanded(
                                              child: AttendanceSummaryCard(
                                                statusByDay: statusByDay,
                                                tilesPerRow:
                                                    inner < 360 ? 2 : 4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  gap,
                                  calendarCard,
                                ],
                              ),
                            ),
                            const SizedBox(width: ParentPortalSpacing.lg),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  interventionsCard,
                                  gap,
                                  disciplineCard,
                                  gap,
                                  documentsCard,
                                ],
                              ),
                            ),
                          ],
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
                backgroundColor: ParentPortalColors.pageBackground(context),
                bottomNavigationBar: compact
                    ? AppBottomNavBar(
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
                          maxWidth: ParentPortalSpacing.maxContentWidth,
                          padding: EdgeInsets.fromLTRB(
                            ParentPortalSpacing.pageHorizontal(context),
                            ParentPortalSpacing.lg,
                            ParentPortalSpacing.pageHorizontal(context),
                            ParentPortalSpacing.xxl,
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
/// shared `NotificationsListView` every staff dashboard's own "View all"
/// swaps into its body, rather than pushing a separate page/route. The
/// list view itself already carries a "Notifications" title, so this only
/// adds the way back to the dashboard.
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
            const SizedBox(width: ParentPortalSpacing.md),
            Text(
              'Back to Dashboard',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ParentPortalColors.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: ParentPortalSpacing.lg),
        switch (view) {
          _MailboxView.notifications => NotificationsListView(
              notifications: notifications,
              isDarkMode: isDarkMode,
            ),
        },
      ],
    );
  }
}
