import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/discipline_officer_mock_data.dart';
import '../../models/discipline_case_model.dart';
import '../../models/good_moral_models.dart';
import '../../models/notification_item_model.dart';
import '../../theme/discipline_officer_colors.dart';
import '../../widgets/email_popover.dart';
import '../../widgets/header_popover_card.dart';
import '../../widgets/logout_confirmation_dialog.dart';
import '../../widgets/notifications_popover.dart';
import '../profile/profile_screen.dart';
import 'email_list_view.dart';
import 'good_moral_view.dart';
import 'notifications_list_view.dart';
import 'violations_view.dart';

/// One selectable row in the Modify dialog's offense dropdown — a
/// `handbook_offenses` row reduced to what the UI needs to display and
/// persist a selection.
class OffenseOption {
  const OffenseOption({
    required this.id,
    required this.label,
    this.category,
  });

  final String id;

  /// `handbook_offenses.description` — the human-readable offense title.
  final String label;

  /// `handbook_offenses.category` (e.g. "Minor", "Major_A"), shown as a
  /// hint alongside [label]. Null for the built-in demo list.
  final String? category;
}

// NotificationItemModel moved to models/notification_item_model.dart —
// shared verbatim with every other module. Good Moral models moved to
// models/good_moral_models.dart so both this file and good_moral_view.dart
// can use them without a circular import.

// ---------------------------------------------------------------------------
// Dashboard tab navigation state
// ---------------------------------------------------------------------------

enum DashboardTab { violations, goodMoral, report, parentalIntervention }

/// "View all notifications"/"View all emails" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [DashboardTab]'s own
/// values since it isn't a real, always-visible tab; tapping any real tab
/// clears this back to null.
enum _MailboxView { notifications, email }

/// Tracks which top-level dashboard view is active. A thin [ValueNotifier]
/// (same pattern as the app's `themeModeController`) so `DashboardHeaderNavBar`
/// and the page body can both react without threading a raw enum + setState
/// callback pair through the widget tree by hand.
class DashboardTabController extends ValueNotifier<DashboardTab> {
  DashboardTabController([super.initialTab = DashboardTab.violations]);

  void selectViolations() => value = DashboardTab.violations;

  void selectGoodMoral() => value = DashboardTab.goodMoral;

  void selectReport() => value = DashboardTab.report;

  void selectParentalIntervention() =>
      value = DashboardTab.parentalIntervention;
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _DashboardColors {
  static const headerBackground = Color(0xFF15253F);
  static Color surfaceBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF0F5F8);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color emptyStateIcon(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);

  // Sits on the navy AppHeaderNavBar only (the officer's name text) — that
  // header never changes with theme, so this stays a plain constant.
  static const gray = Color(0xFFE6E6E6);

  // Top-level DashboardHeaderNavBar (Violations / Good Moral / Report /
  // Parental Intervention) — flat underline-tab style. Its own background
  // is a "surface" sitting on the page (which does change with theme), so
  // it and its inactive-tab text get dark variants too. The active-tab
  // text/indicator are the module's accent blue and stay constant.
  static Color navBarBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static const navBarActiveText = Color(0xFF345892);
  static Color navBarInactiveText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);
  static const navBarIndicator = Color(0xFF345892);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class DisciplineOfficerDashboardPage extends StatefulWidget {
  const DisciplineOfficerDashboardPage({
    super.key,
    this.officerName = 'Juan Dela Cruz',
    this.onReturnToHub,
    this.onSignOut,
    this.initialMetrics,
    this.initialPendingQueue,
    this.initialGoodMoralRequests,
    this.initialStudentDirectory,
    this.availableOffenses,
    this.onResolveCase,
    this.onModifyCase,
    this.onArchiveCase,
    this.onLoadArchivedViolations,
    this.studentDirectoryTotalCount,
    this.studentDirectoryPageSize = 25,
    this.onLoadStudentDirectoryPage,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    this.onGenerateGoodMoralCertificate,
  });

  final String officerName;

  /// Set when Admin opens this page from the hub as a preview; renders a
  /// back button in the header. Null for a Discipline Officer's own direct
  /// login route, where there is no hub to return to.
  final VoidCallback? onReturnToHub;

  /// Renders a sign-out action in the header when set — required for the
  /// direct-login route (no hub app bar to sign out from otherwise).
  final VoidCallback? onSignOut;

  /// Supplies live-data initial state (e.g. wired to Supabase from the host
  /// app). Each falls back to [DisciplineOfficerMockData] when omitted, so
  /// this package stays independently runnable/demoable without a backend.
  final DisciplineSummaryMetricsModel? initialMetrics;
  final List<DisciplineCaseModel>? initialPendingQueue;
  final List<GoodMoralRequestModel>? initialGoodMoralRequests;
  final List<StudentDirectoryEntryModel>? initialStudentDirectory;

  /// Offense choices for the Modify dialog's dropdown (`handbook_offenses`
  /// rows). Falls back to a small built-in list matching the demo data's own
  /// violation-type strings when omitted.
  final List<OffenseOption>? availableOffenses;

  /// Persists Validate/Deny (both simply mark the case `Resolved` — this
  /// schema has no distinct "denied" state) by case id. When omitted, only
  /// local state is mutated (demo behavior).
  final Future<void> Function(String caseId)? onResolveCase;

  /// Persists Modify's edited fields for a case. When omitted, only local
  /// state is mutated (demo behavior).
  final Future<void> Function(
    String caseId, {
    String? offenseId,
    bool? isEscalated,
    String? penaltyImposed,
  })? onModifyCase;

  /// "Delete" on the Preview panel — soft-deletes (archives) a case by id
  /// rather than removing it outright. When omitted, only local state is
  /// mutated (demo behavior).
  final Future<void> Function(String caseId)? onArchiveCase;

  /// Loads reports archived within the last 7 days for the read-only "View
  /// Archived" list. When omitted, the Violation Queue shows no "View
  /// Archived" link at all (demo behavior — there's nothing to archive
  /// against).
  final Future<List<DisciplineCaseModel>> Function()? onLoadArchivedViolations;

  /// Total rows behind the Good Moral Management "Students List" — when
  /// this and [onLoadStudentDirectoryPage] are both supplied, that list
  /// fetches one page at a time (via the callback) instead of expecting
  /// [initialStudentDirectory] to already hold every student.
  final int? studentDirectoryTotalCount;
  final int studentDirectoryPageSize;
  final Future<List<StudentDirectoryEntryModel>> Function(int page)?
      onLoadStudentDirectoryPage;

  /// Notifications targeted at this dashboard from the centralized
  /// notification system (Admin's Notifications page). Falls back to an
  /// empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  /// Builds and shows the Good Moral Certificate for [selected] (the
  /// document generation itself — PDF/DOCX/print — lives in the host app,
  /// not this presentation-only package). Only called when [selected]
  /// doesn't have an active violation; see [_handleGenerateCertificate].
  final Future<void> Function(GoodMoralSelectedStudent selected)?
      onGenerateGoodMoralCertificate;

  @override
  State<DisciplineOfficerDashboardPage> createState() =>
      _DisciplineOfficerDashboardPageState();
}

class _DisciplineOfficerDashboardPageState
    extends State<DisciplineOfficerDashboardPage> {
  // Drives the page's light/dark Theme. Owned locally (rather than by a
  // root MaterialApp, like the source repo's standalone build did) since
  // this page is embedded inside the host app's own MaterialApp. Always
  // light now that the header's Settings entry point (and its Dark Mode
  // toggle) has been removed.
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  // Backend-ready state. `widget.initialX` (wired to Supabase from the host
  // app) wins when supplied; otherwise falls back to DisciplineOfficerMockData
  // so this package stays independently runnable/demoable without a backend.
  late DisciplineSummaryMetricsModel metrics;
  late List<DisciplineCaseModel> pendingQueue;
  DisciplineCaseModel? selectedCase;
  late List<NotificationItemModel> notifications;

  final tabController = DashboardTabController();
  final goodMoralController = GoodMoralDashboardController();

  /// Non-null while "View all notifications"/"View all emails" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;

  bool _resolving = false;

  int _studentDirectoryPage = 1;
  bool _studentDirectoryLoading = false;

  int get _studentDirectoryTotalPages {
    final total = widget.studentDirectoryTotalCount;
    if (total == null || total == 0) return 1;
    return (total + widget.studentDirectoryPageSize - 1) ~/
        widget.studentDirectoryPageSize;
  }

  Future<void> _goToStudentDirectoryPage(int page) async {
    final loader = widget.onLoadStudentDirectoryPage;
    if (loader == null || page < 1) return;
    setState(() => _studentDirectoryLoading = true);
    try {
      final students = await loader(page);
      if (!mounted) return;
      setState(() => _studentDirectoryPage = page);
      goodMoralController.setStudents(students);
    } catch (e) {
      _showErrorSnackBar('Could not load students: $e');
    } finally {
      if (mounted) setState(() => _studentDirectoryLoading = false);
    }
  }

  static const _defaultOffenseOptions = <OffenseOption>[
    OffenseOption(
        id: 'demo-academic-dishonesty', label: 'Major – Academic Dishonesty'),
    OffenseOption(
        id: 'demo-uniform-violation', label: 'Minor – Uniform Violation'),
    OffenseOption(id: 'demo-vandalism', label: 'Major – Vandalism'),
    OffenseOption(
        id: 'demo-late-return', label: 'Minor – Late Return of Equipment'),
    OffenseOption(
        id: 'demo-mobile-phone',
        label: 'Minor – Unauthorized Use of Mobile Phone'),
    OffenseOption(id: 'demo-bullying', label: 'Major – Bullying/Harassment'),
  ];

  List<OffenseOption> get _offenseOptions =>
      widget.availableOffenses ?? _defaultOffenseOptions;

  @override
  void initState() {
    super.initState();
    metrics =
        widget.initialMetrics ?? DisciplineOfficerMockData.getSummaryMetrics();
    pendingQueue = List.of(
      widget.initialPendingQueue ??
          DisciplineOfficerMockData.getPendingViolations(),
    );
    goodMoralController.setRequests(
      widget.initialGoodMoralRequests ??
          DisciplineOfficerMockData.getGoodMoralRequests(),
    );
    goodMoralController.setStudents(
      widget.initialStudentDirectory ??
          DisciplineOfficerMockData.getStudentDirectory(),
    );
    notifications = List.of(widget.initialNotifications ?? const []);
  }

  /// The host app (`DisciplineOfficerConnectedPage`) reloads Supabase data —
  /// e.g. after a realtime `student_violations` change — by rebuilding this
  /// widget with fresh `initialX` lists. `initState` above only seeds local
  /// state once, so without this override that reload silently never
  /// reaches `pendingQueue`/`metrics`/the Good Moral controller, and nothing
  /// this page renders actually updates live. Re-syncs whenever the parent
  /// hands down a new list/metrics instance; preserves the current
  /// selection where its underlying record is still present.
  @override
  void didUpdateWidget(covariant DisciplineOfficerDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final freshQueue = widget.initialPendingQueue;
    if (freshQueue != null &&
        !identical(freshQueue, oldWidget.initialPendingQueue)) {
      setState(() {
        pendingQueue = List.of(freshQueue);
        final current = selectedCase;
        selectedCase =
            current == null ? null : _findCaseById(freshQueue, current.id);
      });
    }

    final freshMetrics = widget.initialMetrics;
    if (freshMetrics != null &&
        !identical(freshMetrics, oldWidget.initialMetrics)) {
      setState(() => metrics = freshMetrics);
    }

    final freshRequests = widget.initialGoodMoralRequests;
    if (freshRequests != null &&
        !identical(freshRequests, oldWidget.initialGoodMoralRequests)) {
      goodMoralController.setRequests(freshRequests);
    }

    final freshStudents = widget.initialStudentDirectory;
    if (freshStudents != null &&
        !identical(freshStudents, oldWidget.initialStudentDirectory)) {
      goodMoralController.setStudents(freshStudents);
    }

    final freshNotifications = widget.initialNotifications;
    if (freshNotifications != null &&
        !identical(freshNotifications, oldWidget.initialNotifications)) {
      setState(() => notifications = List.of(freshNotifications));
    }
  }

  DisciplineCaseModel? _findCaseById(
    List<DisciplineCaseModel> cases,
    String id,
  ) {
    for (final c in cases) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _themeMode.dispose();
    tabController.dispose();
    goodMoralController.dispose();
    super.dispose();
  }

  void _selectCase(DisciplineCaseModel caseItem) {
    setState(() => selectedCase = caseItem);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resolveSelectedCase() async {
    final resolved = selectedCase;
    if (resolved == null || _resolving) return;

    setState(() => _resolving = true);
    try {
      await widget.onResolveCase?.call(resolved.id);
      if (!mounted) return;
      setState(() {
        pendingQueue.removeWhere((c) => c.id == resolved.id);
        selectedCase = null;
        metrics = DisciplineSummaryMetricsModel(
          pendingQueueCount: pendingQueue.length,
          escalatedCount: pendingQueue.where((c) => c.isEscalated).length,
          processedTodayCount: metrics.processedTodayCount + 1,
          avgResponseTimeMinutes: metrics.avgResponseTimeMinutes,
        );
      });
    } catch (e) {
      _showErrorSnackBar('Could not resolve this case: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _handleValidate() => _resolveSelectedCase();

  /// Unlike Validate/Delete, Modify doesn't resolve the case — it opens an
  /// edit screen so the officer can correct the offense, escalation flag,
  /// and penalty notes in place. The case stays in `pendingQueue`; only its
  /// fields change.
  Future<void> _handleModify() async {
    final current = selectedCase;
    if (current == null) return;

    final updated = await showDialog<DisciplineCaseModel>(
      context: context,
      builder: (dialogContext) => _ModifyViolationDialog(
        caseItem: current,
        offenseOptions: _offenseOptions,
      ),
    );
    if (updated == null || !mounted) return;

    try {
      await widget.onModifyCase?.call(
        updated.id,
        offenseId: updated.offenseId,
        isEscalated: updated.isEscalated,
        penaltyImposed: updated.penaltyImposed,
      );
      if (!mounted) return;
      setState(() {
        final index = pendingQueue.indexWhere((c) => c.id == updated.id);
        if (index != -1) pendingQueue[index] = updated;
        selectedCase = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Violation updated.')),
      );
    } catch (e) {
      _showErrorSnackBar('Could not update this case: $e');
    }
  }

  /// Deleting a report doesn't remove it outright — it archives it
  /// (`onArchiveCase`), pulling it from the active queue immediately while
  /// keeping it viewable (read-only) under "View Archived" for 7 days
  /// before it's permanently purged. Confirms first since, unlike Modify,
  /// this can't be undone from this dialog once the retention window ends.
  Future<void> _handleDelete() async {
    final target = selectedCase;
    if (target == null || _resolving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Delete Violation Report?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '"${target.violationType}" for ${target.studentName} will be '
          'removed from the active queue. It stays viewable under "View '
          'Archived" for 7 days, then is permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFCD4855),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resolving = true);
    try {
      await widget.onArchiveCase?.call(target.id);
      if (!mounted) return;
      setState(() {
        pendingQueue.removeWhere((c) => c.id == target.id);
        selectedCase = null;
        metrics = DisciplineSummaryMetricsModel(
          pendingQueueCount: pendingQueue.length,
          escalatedCount: pendingQueue.where((c) => c.isEscalated).length,
          processedTodayCount: metrics.processedTodayCount,
          avgResponseTimeMinutes: metrics.avgResponseTimeMinutes,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Violation report archived.')),
      );
    } catch (e) {
      _showErrorSnackBar('Could not delete this case: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _showArchivedViolations() {
    final loader = widget.onLoadArchivedViolations;
    if (loader == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ArchivedViolationsDialog(loadArchived: loader),
    );
  }

  Future<void> _handleGenerateCertificate() async {
    final selected = goodMoralController.selectedStudentRequest;
    if (selected == null) return;

    if (selected.hasActiveViolation) {
      _showErrorSnackBar(
        '${selected.studentName} has a pending violation and is not '
        'currently eligible for a Good Moral Certificate.',
      );
      return;
    }

    try {
      await widget.onGenerateGoodMoralCertificate?.call(selected);
    } catch (e) {
      _showErrorSnackBar('Could not generate the certificate: $e');
    }
  }

  /// Thin wrapper around the shared [showHeaderPopover] so every call site
  /// below reads the same as before the popovers were extracted into
  /// `widgets/`.
  Future<void> _showHeaderPopover({
    required Widget Function(BuildContext context, StateSetter setPopoverState)
        contentBuilder,
    double cardWidth = 360,
    // True for the profile popover — it anchors just above the bottom nav's
    // Profile icon instead of centering, so it stays visually tethered to
    // what opened it.
    bool anchorAboveBottomNav = false,
  }) {
    final isMobile = context.isMobileWidth;
    return showHeaderPopover(
      context: context,
      contentBuilder: contentBuilder,
      cardWidth: cardWidth,
      // Once the header's icons have moved into the bottom nav bar
      // (mobile), anchoring the popover under the top header reads as
      // disconnected from where it was actually triggered — center it on
      // the screen instead (unless anchorAboveBottomNav asked for the
      // bottom-right anchor instead).
      centered: isMobile && !anchorAboveBottomNav,
      anchorAboveBottomNav: isMobile && anchorAboveBottomNav,
    );
  }

  /// `ProfileScreen` is pushed onto the app's root `Navigator`, so its
  /// subtree lands outside this page's own local `Theme` (the same
  /// Overlay-escapes-local-Theme issue as the header popovers) — wrap it in
  /// a `Theme` matching the current toggle so its `context.isDarkMode`
  /// reads correctly instead of always seeing the app's ambient theme.
  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _DashboardColors.headerBackground,
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: const ProfileScreen(),
    );
  }

  void _openProfile() {
    _showHeaderPopover(
      cardWidth: 260,
      anchorAboveBottomNav: true,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          onViewProfile: () {
            Navigator.of(popoverContext).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => _themedProfileScreen()));
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

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  Future<void> _markNotificationsRead() async {
    if (notifications.every((n) => n.isRead)) return;
    setState(() {
      notifications =
          notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  void _showNotificationsMenu() {
    _showHeaderPopover(
      cardWidth: 400,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: notifications,
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

  void _showEmailMenu() {
    _showHeaderPopover(
      cardWidth: 400,
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: _DashboardColors.headerBackground,
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
    final isDarkMode = _themeMode.value == ThemeMode.dark;

    final header = AppHeaderNavBar(
      title: 'Student Affairs & Services',
      subtitle: 'Mission Control',
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onReturnToHub != null) ...[
            HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: widget.onReturnToHub!,
            ),
            const SizedBox(width: 12),
          ],
          const SchoolLogo(),
        ],
      ),
      actions: [
        if (!isMobile) ...[
          HeaderIconButton(
            icon: Icons.mail_outline_rounded,
            onTap: _showEmailMenu,
          ),
          HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            badgeCount: notifications.where((n) => !n.isRead).length,
            onTap: _showNotificationsMenu,
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _themedProfileScreen()),
                ),
                child: Text(
                  widget.officerName,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: _DashboardColors.gray,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              ProfileAvatarButton(onTap: _openProfile),
              if (widget.onSignOut != null) ...[
                const SizedBox(width: 10),
                HeaderIconButton(
                  icon: Icons.logout_rounded,
                  onTap: widget.onSignOut!,
                ),
              ],
            ],
          ),
        ] else if (widget.onSignOut != null)
          HeaderIconButton(
            icon: Icons.logout_rounded,
            onTap: widget.onSignOut!,
          ),
      ],
    );

    // Tab bar + main content share the same 1440px-capped, centered frame
    // every dashboard module uses (see DashboardPageWrapper).
    final pageContent = DashboardPageWrapper(
      // On mobile the cards should use nearly the full screen width instead
      // of losing 48px total to the desktop's 24px side margins.
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 5 : 24,
        vertical: 16,
      ),
      child: ValueListenableBuilder<DashboardTab>(
        valueListenable: tabController,
        builder: (context, activeTab, _) {
          final navBar = DashboardHeaderNavBar(
            activeTab: activeTab,
            onTabSelected: (tab) {
              setState(() => _mailboxView = null);
              tabController.value = tab;
            },
          );

          // Every card sizes to its own content instead of being squeezed
          // into a fixed Expanded share of the viewport (that's what caused
          // the overflow — an Expanded panel forced into less height than
          // its content needs). The whole page — including the header, see
          // body below — scrolls instead, so nothing has to shrink past its
          // natural size.
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              navBar,
              const SizedBox(height: 16),
              _buildBody(activeTab, isMobile: isMobile),
            ],
          );
        },
      ),
    );

    return Scaffold(
      backgroundColor: _DashboardColors.surfaceBackground(context),
      bottomNavigationBar: isMobile
          ? AppBottomNavBar(
              onEmailTap: _showEmailMenu,
              onNotificationTap: _showNotificationsMenu,
              onProfileTap: _openProfile,
              notificationBadgeCount:
                  notifications.where((n) => !n.isRead).length,
              isDarkMode: isDarkMode,
            )
          : null,
      // The whole body is one scrollable column so a short viewport never
      // clips tab content with no way to reach the rest of it.
      body: SingleChildScrollView(
        child: Column(children: [header, pageContent]),
      ),
    );
  }

  Widget _buildBody(DashboardTab activeTab, {required bool isMobile}) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: notifications,
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case _MailboxView.email:
        return EmailListView(isDarkMode: _themeMode.value == ThemeMode.dark);
      case null:
        return _buildTabContent(activeTab, isMobile: isMobile);
    }
  }

  Widget _buildTabContent(DashboardTab activeTab, {required bool isMobile}) {
    return switch (activeTab) {
      DashboardTab.violations => _buildViolationsContent(isMobile: isMobile),
      DashboardTab.goodMoral => _buildGoodMoralContent(isMobile: isMobile),
      DashboardTab.report => _emptySection(
          icon: Icons.fact_check_outlined,
          title: 'Report',
          subtitle: 'CHED reporting is not available yet',
        ),
      DashboardTab.parentalIntervention => _emptySection(
          icon: Icons.groups_outlined,
          title: 'Parental Intervention',
          subtitle: 'Parental intervention records are not available yet',
        ),
    };
  }

  Widget _emptySection({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return _EmptySectionView(icon: icon, title: title, subtitle: subtitle);
  }

  Widget _buildViolationsContent({required bool isMobile}) {
    final queueCard = ValidationQueueCard(
      cases: pendingQueue,
      selectedCaseId: selectedCase?.id,
      onSelect: _selectCase,
      onViewArchived: widget.onLoadArchivedViolations == null
          ? null
          : _showArchivedViolations,
    );

    final detailsPanel = ViolationPreviewPanel(
      selectedCase: selectedCase,
      onValidate: _handleValidate,
      onModify: _handleModify,
      onDelete: _handleDelete,
    );

    // Stats cards always come first, above the queue — both here and in the
    // desktop LayoutBuilder below.
    final statsRow = ViolationStatsRow(metrics: metrics);

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statsRow,
          const SizedBox(height: 18),
          queueCard,
          const SizedBox(height: 16),
          detailsPanel,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        final queueAndDetails = stackColumns
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  queueCard,
                  const SizedBox(height: 16),
                  detailsPanel,
                ],
              )
            // Master-detail: the queue "sidebar" is height-locked to match
            // the Preview panel (CrossAxisAlignment.stretch), capped so the
            // pair never grows past ~one viewport — the queue's own list
            // scrolls internally within that fixed height instead.
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: context.masterDetailRowMaxHeight(),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: queueCard),
                    const SizedBox(width: 18),
                    Expanded(child: detailsPanel),
                  ],
                ),
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statsRow,
            const SizedBox(height: 18),
            queueAndDetails,
          ],
        );
      },
    );
  }

  Widget _buildGoodMoralContent({required bool isMobile}) {
    return GoodMoralManagementView(
      controller: goodMoralController,
      onGenerateCertificate: _handleGenerateCertificate,
      studentDirectoryPage: _studentDirectoryPage,
      studentDirectoryTotalPages: _studentDirectoryTotalPages,
      studentDirectoryTotalCount: widget.studentDirectoryTotalCount,
      studentDirectoryLoading: _studentDirectoryLoading,
      onStudentDirectoryPageChanged: widget.onLoadStudentDirectoryPage == null
          ? null
          : _goToStudentDirectoryPage,
      isMobile: isMobile,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty placeholder section (Report / Parental Intervention)
// ---------------------------------------------------------------------------

/// Generic "nothing here yet" section for tabs that don't have a data model
/// or workflow defined yet. Mirrors the visual language of the queue/detail
/// empty states (rounded-square icon badge, title, subtitle) so a bare tab
/// doesn't look broken while its real content is built out.
class _EmptySectionView extends StatelessWidget {
  const _EmptySectionView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _DashboardColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DashboardColors.cardBorder(context)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                // Soft-tint icon badge — richer/darker blue tint on a dark
                // card so it stays legible instead of glaring white.
                color: context.isDarkMode
                    ? const Color(0xFF1E3A5F)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 32,
                color: _DashboardColors.emptyStateIcon(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 16 : 18,
                fontWeight: FontWeight.w700,
                color: _DashboardColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 12 : 14,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-level header navigation bar (Violations / Good Moral / Report /
// Parental Intervention)
// ---------------------------------------------------------------------------

/// Full-width underline-tab bar rendered directly below [_DashboardHeader]
/// and above the padded content area. Distinct from [_DashboardTabButton]
/// (the pill-style buttons used by the Good Moral Requests/Students List
/// sub-tabs), which keeps its own filled-background look.
class DashboardHeaderNavBar extends StatelessWidget {
  const DashboardHeaderNavBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  final DashboardTab activeTab;
  final ValueChanged<DashboardTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.navBarBackground(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DashboardColors.cardBorder(context)),
      ),
      // Horizontally scrollable — at mobile widths the four tab labels plus
      // spacing don't fit the viewport, and this bar has no business
      // shrinking or wrapping them (matches Figma's own `overflow-x-auto`
      // on this bar). The Container's own fixed height:48 still bounds the
      // Row's cross axis, so nothing overflows vertically either.
      // ScrollConfiguration: Flutter's default ScrollBehavior excludes
      // mouse from dragDevices, which would otherwise leave the overflowing
      // tabs unreachable for a desktop mouse user (touch/trackpad drag
      // still worked; a plain click-drag or scroll didn't).
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            // Stretch so every _DashboardNavBarItem spans the bar's full
            // 48px height, letting its indicator's Positioned(bottom: 0)
            // land flush on the container's own bottom edge (on top of
            // navBarBorder) instead of being inset by the row's own
            // vertical centering.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DashboardNavBarItem(
                label: 'Violations',
                icon: Icons.assignment_late_outlined,
                isActive: activeTab == DashboardTab.violations,
                onTap: () => onTabSelected(DashboardTab.violations),
              ),
              const SizedBox(width: 45),
              _DashboardNavBarItem(
                label: 'Good Moral',
                icon: Icons.verified_outlined,
                isActive: activeTab == DashboardTab.goodMoral,
                onTap: () => onTabSelected(DashboardTab.goodMoral),
              ),
              const SizedBox(width: 45),
              _DashboardNavBarItem(
                label: 'Parental Intervention',
                icon: Icons.family_restroom_outlined,
                isActive: activeTab == DashboardTab.parentalIntervention,
                onTap: () => onTabSelected(DashboardTab.parentalIntervention),
              ),
              const SizedBox(width: 45),
              _DashboardNavBarItem(
                label: 'Compliance Report',
                icon: Icons.summarize_outlined,
                isActive: activeTab == DashboardTab.report,
                onTap: () => onTabSelected(DashboardTab.report),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardNavBarItem extends StatelessWidget {
  const _DashboardNavBarItem({
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
    final color = isActive
        ? _DashboardColors.navBarActiveText
        : _DashboardColors.navBarInactiveText(context);
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Stack(
        // No padding/margin wrapping this Stack: it takes the item's full
        // stretched height from the parent Row, so `bottom: 0` below is the
        // container's actual bottom edge, not an inset placeholder.
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Center(
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: isActive
                    ? _DashboardColors.navBarIndicator
                    : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account popover — anchored below the header's profile avatar.
// ---------------------------------------------------------------------------

/// Compact "Profile / Dark Mode / Logout" dropdown opened from the header's
/// avatar button (Figma node 488:1105) — narrower and plainer than
/// [HeaderPopoverCard] (used by Notifications/Settings), so it builds its
/// own card chrome instead of reusing that shell.
class AccountProfileMenu extends StatelessWidget {
  const AccountProfileMenu({
    super.key,
    required this.onViewProfile,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.onLogout,
  });

  final VoidCallback onViewProfile;

  /// Current theme state — flips the "Dark Mode" row's label to "Light
  /// Mode" once dark mode is active.
  final bool isDarkMode;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    // This popover renders through `showMenu`'s own Overlay/route (see
    // `showHeaderPopover`), which sits outside the dashboard page's local
    // per-page Theme — so `context.isDarkMode` here would read the app's
    // ambient theme, not this page's toggle. [isDarkMode] is threaded in
    // explicitly instead, same as the existing "Dark Mode"/"Light Mode"
    // label logic above.
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 260,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF16191D) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isDarkMode
                  ? const Color(0x0D334155)
                  : const Color(0x0D000000)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AccountMenuItem(
              label: 'Profile',
              onTap: onViewProfile,
              isDarkMode: isDarkMode,
            ),
            _AccountMenuItem(
              label: isDarkMode ? 'Light Mode' : 'Dark Mode',
              onTap: onToggleDarkMode,
              isDarkMode: isDarkMode,
            ),
            _AccountMenuItem(
              label: 'Logout',
              onTap: onLogout,
              showDivider: false,
              isDarkMode: isDarkMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({
    required this.label,
    required this.onTap,
    required this.isDarkMode,
    this.showDivider = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDarkMode;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: showDivider
            ? BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: isDarkMode
                            ? const Color(0x0D334155)
                            : const Color(0x0D000000))),
              )
            : null,
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 14 : 16,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? const Color(0xFFF1F5F9) : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only list opened by the Violation Queue's "View Archived" link —
/// reports "deleted" via [_handleDelete] within their 7-day retention
/// window (see `DisciplineRepository.fetchArchivedViolations`). No actions
/// beyond viewing; once the window passes, the report is gone the next time
/// this list loads.
class _ArchivedViolationsDialog extends StatefulWidget {
  const _ArchivedViolationsDialog({required this.loadArchived});

  final Future<List<DisciplineCaseModel>> Function() loadArchived;

  @override
  State<_ArchivedViolationsDialog> createState() =>
      _ArchivedViolationsDialogState();
}

class _ArchivedViolationsDialogState extends State<_ArchivedViolationsDialog> {
  late final Future<List<DisciplineCaseModel>> _future = widget.loadArchived();

  /// Matches `DisciplineRepository.archiveRetention` — kept as a literal
  /// here since this presentation-only package can't depend on the app's
  /// data layer.
  static const _retentionDays = 7;

  String _purgeLabel(DateTime? archivedAt) {
    if (archivedAt == null) return '';
    final daysLeft =
        _retentionDays - DateTime.now().difference(archivedAt).inDays;
    if (daysLeft <= 0) return 'Purges soon';
    return 'Purges in $daysLeft day${daysLeft == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Archived Violation Reports',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 460,
        height: 420,
        child: FutureBuilder<List<DisciplineCaseModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child:
                    Text('Could not load archived reports: ${snapshot.error}'),
              );
            }
            final archived = snapshot.data ?? const [];
            if (archived.isEmpty) {
              return const Center(child: Text('No archived reports.'));
            }
            return ListView.separated(
              itemCount: archived.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = archived[index];
                return ListTile(
                  title: Text(
                    '${item.studentName} · ${item.studentNumber}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${item.violationType}\n${_purgeLabel(item.archivedAt)}',
                  ),
                  isThreeLine: true,
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Edit screen opened by the "Modify" action — lets the officer reclassify
/// the offense, adjust the escalation flag, and record penalty/notes before
/// saving the case back in place (see `_handleModify`). Fields are limited
/// to what `student_violations` actually stores per-case — there's no
/// free-text violation-type or location column, only `offense_id` (a link
/// into `handbook_offenses`), `is_escalated`, and `penalty_imposed`. Returns
/// the updated [DisciplineCaseModel] via `Navigator.pop`, or `null` if
/// cancelled.
class _ModifyViolationDialog extends StatefulWidget {
  const _ModifyViolationDialog({
    required this.caseItem,
    required this.offenseOptions,
  });

  final DisciplineCaseModel caseItem;
  final List<OffenseOption> offenseOptions;

  @override
  State<_ModifyViolationDialog> createState() => _ModifyViolationDialogState();
}

class _ModifyViolationDialogState extends State<_ModifyViolationDialog> {
  late final _penaltyController = TextEditingController(
    text: widget.caseItem.penaltyImposed ?? '',
  );
  late bool _isEscalated = widget.caseItem.isEscalated;
  String? _selectedOffenseId;

  @override
  void initState() {
    super.initState();
    final currentId = widget.caseItem.offenseId;
    _selectedOffenseId = widget.offenseOptions.any((o) => o.id == currentId)
        ? currentId
        : (widget.offenseOptions.isEmpty
            ? null
            : widget.offenseOptions.first.id);
  }

  @override
  void dispose() {
    _penaltyController.dispose();
    super.dispose();
  }

  void _save() {
    final offenseId = _selectedOffenseId;
    final offenseLabel = widget.offenseOptions
        .where((o) => o.id == offenseId)
        .map((o) => o.label)
        .firstOrNull;

    Navigator.of(context).pop(
      widget.caseItem.copyWith(
        offenseId: offenseId,
        violationType: offenseLabel ?? widget.caseItem.violationType,
        isEscalated: _isEscalated,
        penaltyImposed: _penaltyController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Modify Violation',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.caseItem.studentName} · ${widget.caseItem.studentNumber}',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  color: _DashboardColors.secondaryText(context),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedOffenseId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Offense',
                  border: OutlineInputBorder(),
                ),
                items: widget.offenseOptions
                    .map(
                      (o) => DropdownMenuItem(
                        value: o.id,
                        child: Text(
                          o.category == null
                              ? o.label
                              : '${o.label} (${o.category})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedOffenseId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _penaltyController,
                decoration: const InputDecoration(
                  labelText: "Officer's Notes / Penalty",
                  helperText:
                      'Shown separately from the original report notes on the case preview.',
                  border: OutlineInputBorder(),
                ),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Escalate to Security'),
                value: _isEscalated,
                onChanged: (value) => setState(() => _isEscalated = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ---------------------------------------------------------------------------
// Good Moral Management — Requests / Students List queue + Preview panel
// ---------------------------------------------------------------------------

/// Standalone Good Moral Management view: a left sidebar that switches
/// between the pending Requests queue and the full Students List directory,
/// and a right Preview panel that reviews whichever student is selected and
/// lets the officer generate + print a Good Moral certificate for them.
class GoodMoralManagementView extends StatelessWidget {
  const GoodMoralManagementView({
    super.key,
    required this.controller,
    required this.onGenerateCertificate,
    this.studentDirectoryPage = 1,
    this.studentDirectoryTotalPages = 1,
    this.studentDirectoryTotalCount,
    this.studentDirectoryLoading = false,
    this.onStudentDirectoryPageChanged,
    this.isMobile = false,
  });

  final GoodMoralDashboardController controller;
  final VoidCallback onGenerateCertificate;

  /// Pagination for the "Students List" sub-tab — when
  /// [onStudentDirectoryPageChanged] is null (the default/demo path), the
  /// sidebar just shows every student in [controller] with no page footer.
  final int studentDirectoryPage;
  final int studentDirectoryTotalPages;
  final int? studentDirectoryTotalCount;
  final bool studentDirectoryLoading;
  final ValueChanged<int>? onStudentDirectoryPageChanged;

  /// True when the page has no bounded height to hand this view (it scrolls
  /// instead) — the preview panel sizes itself to its own content rather
  /// than filling an `Expanded` share of the viewport.
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isRequestsTab =
            controller.activeSubTab == GoodMoralSubTab.requests;

        final rows = isRequestsTab
            ? controller.requests
                .map((r) => GoodMoralQueueRowData(
                      id: r.id,
                      name: r.studentName,
                      section: r.programGradeSection,
                      number: r.studentNumber,
                    ))
                .toList()
            : controller.students
                .map((s) => GoodMoralQueueRowData(
                      id: s.id,
                      name: s.studentName,
                      section: s.programGradeSection,
                      number: s.studentNumber,
                      groupLabel: s.program.isEmpty
                          ? null
                          : '${s.program} — Year ${s.yearLevel}',
                    ))
                .toList();

        final selectedId = controller.selectedStudentRequest?.sourceSubTab ==
                controller.activeSubTab
            ? controller.selectedStudentRequest?.sourceId
            : null;

        final queueCard = GoodMoralQueueCard(
          title: isRequestsTab ? 'Requests' : 'Student List',
          totalCountLabel: isRequestsTab
              ? 'Total requests: ${controller.requests.length}'
              : 'Total students: ${controller.students.length}',
          rows: rows,
          selectedId: selectedId,
          isLoading: !isRequestsTab && studentDirectoryLoading,
          footer: !isRequestsTab && onStudentDirectoryPageChanged != null
              ? _StudentDirectoryPaginationFooter(
                  currentPage: studentDirectoryPage,
                  totalPages: studentDirectoryTotalPages,
                  totalCount: studentDirectoryTotalCount,
                  isLoading: studentDirectoryLoading,
                  onPrevious: () =>
                      onStudentDirectoryPageChanged!(studentDirectoryPage - 1),
                  onNext: () =>
                      onStudentDirectoryPageChanged!(studentDirectoryPage + 1),
                )
              : null,
          onSelect: (row) {
            if (isRequestsTab) {
              final request =
                  controller.requests.firstWhere((r) => r.id == row.id);
              controller.selectRequest(request);
            } else {
              final student =
                  controller.students.firstWhere((s) => s.id == row.id);
              controller.selectStudent(student);
            }
          },
        );

        final preview = GoodMoralPreviewPanel(
          selected: controller.selectedStudentRequest,
          onGenerateCertificate: onGenerateCertificate,
        );

        // Header (sub-tab bar) stays fixed; queueCard becomes the flexible
        // child — filling the rest of this column's height — only when an
        // ancestor (the desktop master-detail Row below) actually gives
        // this column a bounded height to fill. Same LayoutBuilder
        // technique as inside the queue cards themselves.
        final leftColumn = LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                GoodMoralSubTabBar(
                  activeTab: controller.activeSubTab,
                  onTabSelected: controller.selectSubTab,
                ),
                const SizedBox(height: 16),
                bounded ? Expanded(child: queueCard) : queueCard,
              ],
            );
          },
        );

        if (isMobile) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              leftColumn,
              const SizedBox(height: 16),
              preview,
            ],
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final stackColumns = constraints.maxWidth < 900;

            if (stackColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  leftColumn,
                  const SizedBox(height: 16),
                  preview,
                ],
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: context.masterDetailRowMaxHeight(),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: leftColumn),
                  const SizedBox(width: 18),
                  Expanded(child: preview),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StudentDirectoryPaginationFooter extends StatelessWidget {
  const _StudentDirectoryPaginationFooter({
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.isLoading,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final bool isLoading;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            totalCount == null
                ? 'Page $currentPage of $totalPages'
                : 'Page $currentPage of $totalPages · $totalCount total',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 9 : 11,
                color: _DashboardColors.secondaryText(context)),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaginationPillButton(
              label: 'Previous',
              background: DisciplineOfficerColors.background(context),
              foreground: DisciplineOfficerColors.azureBlue,
              onTap: (isLoading || currentPage <= 1) ? null : onPrevious,
            ),
            const SizedBox(width: 8),
            PaginationPillButton(
              label: 'Next',
              background: DisciplineOfficerColors.azureBlue,
              foreground: Colors.white,
              onTap:
                  (isLoading || currentPage >= totalPages) ? null : onNext,
            ),
          ],
        ),
      ],
    );
  }
}

// Notifications dropdown moved to widgets/notifications_popover.dart —
// shared verbatim with every other module.
