import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/discipline_officer_mock_data.dart';
import '../../models/discipline_case_model.dart';
import '../../models/good_moral_models.dart';
import '../../models/notification_item_model.dart';
import '../../theme/discipline_officer_colors.dart';
import '../../widgets/header_popover_card.dart';
import '../../widgets/logout_confirmation_dialog.dart';
import '../../widgets/notifications_popover.dart';
import '../profile/profile_screen.dart';
import 'classify_dialog.dart';
import 'good_moral_view.dart';
import 'sanction_dialog.dart';
import '../../models/escalation_report_model.dart';
import 'endorsements_view.dart';
import '../../models/concern_report_model.dart';
import '../investigations/investigations_view.dart';
import '../concerns/concerns_view.dart';
import 'notifications_list_view.dart';
import 'violation_history_view.dart';
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

enum DashboardTab {
  violations,
  violationHistory,
  goodMoral,
  parentalIntervention,
  concerns,
  investigations,
}

/// "View all notifications" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [DashboardTab]'s own
/// values since it isn't a real, always-visible tab; tapping any real tab
/// clears this back to null.
enum _MailboxView { notifications }

/// Tracks which top-level dashboard view is active. A thin [ValueNotifier]
/// (same pattern as the app's `themeModeController`) so `DashboardHeaderNavBar`
/// and the page body can both react without threading a raw enum + setState
/// callback pair through the widget tree by hand.
class DashboardTabController extends ValueNotifier<DashboardTab> {
  DashboardTabController([super.initialTab = DashboardTab.violations]);

  void selectViolations() => value = DashboardTab.violations;

  void selectViolationHistory() => value = DashboardTab.violationHistory;

  void selectGoodMoral() => value = DashboardTab.goodMoral;

  void selectParentalIntervention() =>
      value = DashboardTab.parentalIntervention;

  void selectConcerns() => value = DashboardTab.concerns;

  void selectInvestigations() => value = DashboardTab.investigations;
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

// Dark-mode values below use the app-wide neutral near-black palette
// (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
// A1A1AA/71717A text) — light mode is untouched.
abstract final class _DashboardColors {
  static const headerBackground = Color(0xFF15253F);

  // Each token has a `...For(bool dark)` form besides the BuildContext one.
  // The page's State methods (opening dialogs and sheets) have a `context`
  // that sits ABOVE the Theme the page builds for itself, so
  // `context.isDarkMode` there reads the app theme, not the dashboard's own
  // toggle — they pass the toggle's value instead.
  static Color surfaceBackgroundFor(bool dark) =>
      dark ? const Color(0xFF0E0E0E) : const Color(0xFFF0F5F8);
  static Color cardFor(bool dark) =>
      dark ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color cardBorderFor(bool dark) => dark
      ? const Color(0xFF22242B)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryTextFor(bool dark) =>
      dark ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryTextFor(bool dark) =>
      dark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);

  static Color surfaceBackground(BuildContext context) =>
      surfaceBackgroundFor(context.isDarkMode);
  static Color card(BuildContext context) => cardFor(context.isDarkMode);
  static Color cardBorder(BuildContext context) =>
      cardBorderFor(context.isDarkMode);
  static Color primaryText(BuildContext context) =>
      primaryTextFor(context.isDarkMode);
  static Color secondaryText(BuildContext context) =>
      secondaryTextFor(context.isDarkMode);

  // Top-level DashboardHeaderNavBar (Violations / Good Moral /
  // Parental Intervention) — flat underline-tab style. Its own background
  // is a "surface" sitting on the page (which does change with theme), so
  // it and its inactive-tab text get dark variants too. The active-tab
  // text/indicator are the module's accent blue and stay constant.
  static Color navBarBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static const navBarActiveText = Color(0xFF345892);
  static Color navBarInactiveText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF8F8F8F);
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
    this.initialViolationHistory,
    this.initialGoodMoralRequests,
    this.initialStudentDirectory,
    this.isLoading = false,
    this.availableOffenses,
    this.onClassifyCase,
    this.onAutoRecordCase,
    this.onEscalateCase,
    this.onSanctionCase,
    this.onLoadEvidence,
    this.onLoadCaseHistory,
    this.onModifyCase,
    this.onArchiveCase,
    this.onLoadArchivedViolations,
    this.onRestoreArchived,
    this.onDeleteArchivedViolations,
    this.escalationReports,
    this.onIssueEscalation,
    this.onLoadEndorsementStudents,
    this.onOpenAnalysis,
    this.studentConcerns,
    this.onUpdateConcern,
    this.investigations,
    this.onScheduleMeeting,
    this.onSetMeetingOutcome,
    this.onCompleteInvestigation,
    this.onLoadInvestigationEvidence,
    this.studentDirectoryTotalCount,
    this.studentDirectoryPageSize = 25,
    this.onLoadStudentDirectoryPage,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    this.onMarkNotificationRead,
    this.onGenerateGoodMoralCertificate,
    this.onFlagGoodMoralRequest,
    this.onUseRegistrarRecordGoodMoral,
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

  /// Every violation on record — every status — for the Students Violation
  /// History tab. When omitted it falls back to [initialPendingQueue] if that
  /// was supplied, else to demo data.
  final List<DisciplineCaseModel>? initialViolationHistory;
  final List<GoodMoralRequestModel>? initialGoodMoralRequests;
  final List<StudentDirectoryEntryModel>? initialStudentDirectory;

  /// `true` while the host is still fetching this dashboard's data — the
  /// header and sub-nav render immediately and only the tab content below
  /// them shows a skeleton, instead of the host blocking the whole screen.
  final bool isLoading;

  /// Offense choices for the Modify dialog's dropdown (`handbook_offenses`
  /// rows). Falls back to a small built-in list matching the demo data's own
  /// violation-type strings when omitted.
  final List<OffenseOption>? availableOffenses;

  /// The officer classifies a report the reporter filed without a violation:
  /// the chosen handbook offense ids. When omitted, only local state changes.
  final Future<void> Function(String caseId, List<String> offenseIds)?
      onClassifyCase;

  /// One-click path for a classified Minor case: records the handbook sanction
  /// and closes the case.
  final Future<void> Function(String caseId)? onAutoRecordCase;

  /// Starts an investigation for a classified case.
  final Future<void> Function(String caseId)? onEscalateCase;

  /// Records the sanction that ends a case (see [SanctionDialog]).
  final Future<void> Function(String caseId, SanctionFormResult result)?
      onSanctionCase;

  /// Loads what has been done on a case (who, what, when) for the preview
  /// panel's "Case history". The section is hidden when omitted.
  final Future<List<ViolationActionEntry>> Function(String caseId)?
      onLoadCaseHistory;

  /// Signed viewing links for a case's photo evidence, keyed by storage path.
  final Future<Map<String, String>> Function(List<String> paths)?
      onLoadEvidence;

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

  /// Loads every archived report (manually deleted or expired after 72
  /// hours) for the "View Archived" list. When omitted, the Violation Queue shows no "View
  /// Archived" link at all (demo behavior — there's nothing to archive
  /// against).
  final Future<List<DisciplineCaseModel>> Function()? onLoadArchivedViolations;

  /// The one archive action: Restore returns an archived report to the active
  /// queue (by case id). When omitted the Restore button is hidden.
  final Future<void> Function(String caseId)? onRestoreArchived;

  /// Permanently deletes archived reports (the "Delete selected" / "Delete
  /// all" actions in the archive). The archive shows no delete controls
  /// when omitted.
  final Future<void> Function(List<String> caseIds)?
      onDeleteArchivedViolations;

  /// Endorsements tab: endorsements (with their Guidance Associate approval
  /// status) and the action that files a new one. When [onIssueEscalation] is
  /// omitted the Endorse button is hidden (demo). [onLoadEndorsementStudents]
  /// pages and searches the student list; without it the demo list
  /// ([initialStudentDirectory]) is filtered locally.
  final List<EscalationReportModel>? escalationReports;
  final Future<void> Function(EscalationDraft draft)? onIssueEscalation;
  final LoadEndorsementStudents? onLoadEndorsementStudents;

  /// Opens the ML overview and single/batch student analysis, the same
  /// screens the Guidance Associate uses. Null hides the Analysis entry.
  final VoidCallback? onOpenAnalysis;

  /// Concerns tab: support requests students filed from their own dashboard.
  /// [onUpdateConcern] null makes the tab read-only (demo); the Endorse action
  /// needs [onIssueEscalation].
  final List<ConcernReportModel>? studentConcerns;
  final Future<void> Function(
    ConcernReportModel concern, {
    required String status,
    String? note,
  })? onUpdateConcern;

  /// Investigations tab: cases under investigation with their meetings. The
  /// callbacks are null in demo mode (read-only).
  final List<InvestigationModel>? investigations;
  final Future<void> Function(
    InvestigationModel investigation,
    DateTime scheduledAt,
    String? location,
    String invitee,
  )? onScheduleMeeting;
  final Future<void> Function(InvestigationMeetingModel meeting, String status)?
      onSetMeetingOutcome;
  final Future<void> Function(
    InvestigationModel investigation,
    String findings,
    String? recommendation,
  )? onCompleteInvestigation;
  final Future<Map<String, String>> Function(List<String> paths)?
      onLoadInvestigationEvidence;

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

  /// Saves that one notification was read (by id) — called when its details
  /// are opened. When omitted the read mark is local only.
  final Future<void> Function(String notificationId)? onMarkNotificationRead;

  /// Builds and shows the Good Moral Certificate for [selected] (the
  /// document generation itself — PDF/DOCX/print — lives in the host app,
  /// not this presentation-only package). Only called when [selected]
  /// doesn't have an active violation; see [_handleGenerateCertificate].
  final Future<void> Function(GoodMoralSelectedStudent selected)?
      onGenerateGoodMoralCertificate;

  /// Flags a Good Moral request, or sends it back to the student when
  /// `sendBack` is true. Null hides both actions (demo).
  final Future<void> Function(
    GoodMoralSelectedStudent request,
    String note,
    bool sendBack,
  )? onFlagGoodMoralRequest;

  /// Replaces a Good Moral slip's name, student number and section with the
  /// registrar's record. Null hides the action.
  final Future<void> Function(GoodMoralSelectedStudent request)?
      onUseRegistrarRecordGoodMoral;

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
  final ValueNotifier<ThemeMode> _themeMode = PersistedThemeModeNotifier();

  // Backend-ready state. `widget.initialX` (wired to Supabase from the host
  // app) wins when supplied; otherwise falls back to DisciplineOfficerMockData
  // so this package stays independently runnable/demoable without a backend.
  late DisciplineSummaryMetricsModel metrics;
  late List<DisciplineCaseModel> pendingQueue;
  late List<DisciplineCaseModel> violationHistory;
  DisciplineCaseModel? selectedCase;
  late List<NotificationItemModel> notifications;

  final tabController = DashboardTabController();
  final goodMoralController = GoodMoralDashboardController();

  /// Non-null while "View all notifications" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;

  bool _resolving = false;
  final _evidenceUrls = <String, String>{};

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
    violationHistory = List.of(
      widget.initialViolationHistory ??
          (widget.initialPendingQueue != null
              ? pendingQueue
              : DisciplineOfficerMockData.getViolationHistory()),
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

    // A different server page size (the window crossed the phone breakpoint)
    // means the host refetched the Student List from its first page.
    if (widget.studentDirectoryPageSize != oldWidget.studentDirectoryPageSize) {
      _studentDirectoryPage = 1;
    }

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

    final freshHistory = widget.initialViolationHistory;
    if (freshHistory != null &&
        !identical(freshHistory, oldWidget.initialViolationHistory)) {
      setState(() => violationHistory = List.of(freshHistory));
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
    _loadEvidenceFor(caseItem);
  }

  Future<void> _loadEvidenceFor(DisciplineCaseModel caseItem) async {
    final loader = widget.onLoadEvidence;
    final missing = [
      for (final p in caseItem.evidencePaths)
        if (!_evidenceUrls.containsKey(p)) p,
    ];
    if (loader == null || missing.isEmpty) return;
    try {
      final urls = await loader(missing);
      if (!mounted) return;
      setState(() => _evidenceUrls.addAll(urls));
    } catch (e) {
      debugPrint('Could not load evidence photos: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Rewrites history entry [id] (if it is there) through [change] — keeps the
  /// Students Violation History tab in step with what the queue just did.
  void _updateHistory(
    String id,
    DisciplineCaseModel Function(DisciplineCaseModel) change,
  ) {
    final index = violationHistory.indexWhere((c) => c.id == id);
    if (index != -1) violationHistory[index] = change(violationHistory[index]);
  }

  /// Runs one workflow action on the selected case: guards double taps, shows
  /// a message either way, and updates local state so the queue reflects it
  /// at once (the host reloads and replaces it with the real rows).
  Future<void> _runWorkflow({
    required String errorPrefix,
    required String successMessage,
    required Future<void>? Function() action,
    required DisciplineCaseModel Function(DisciplineCaseModel) update,
    bool closesCase = false,
  }) async {
    final target = selectedCase;
    if (target == null || _resolving) return;
    setState(() => _resolving = true);
    try {
      await action();
      if (!mounted) return;
      final changed = update(target);
      setState(() {
        if (closesCase) {
          pendingQueue.removeWhere((c) => c.id == target.id);
          selectedCase = null;
          metrics = DisciplineSummaryMetricsModel(
            pendingQueueCount: pendingQueue.length,
            escalatedCount: pendingQueue.where((c) => c.isEscalated).length,
            processedTodayCount: metrics.processedTodayCount + 1,
            avgResponseTimeMinutes: metrics.avgResponseTimeMinutes,
          );
        } else {
          final index = pendingQueue.indexWhere((c) => c.id == target.id);
          if (index != -1) pendingQueue[index] = changed;
          selectedCase = changed;
        }
        _updateHistory(target.id, (_) => changed);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      _showErrorSnackBar('$errorPrefix: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _handleClassify() async {
    final current = selectedCase;
    if (current == null || _resolving) return;
    final theme = _pageTheme;
    final ids = await showAppPopup<List<String>>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: ClassifyDialog(
          caseItem: current,
          offenseOptions: _offenseOptions,
        ),
      ),
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final chosen =
        _offenseOptions.where((o) => o.id == ids.first).firstOrNull;
    await _runWorkflow(
      errorPrefix: 'Could not classify this report',
      successMessage: ids.length == 1
          ? 'Report classified.'
          : 'Report classified under ${ids.length} violations.',
      action: () => widget.onClassifyCase?.call(current.id, ids),
      update: (c) => c.copyWith(
        offenseId: ids.first,
        violationType: chosen?.label,
        offenseCategory: chosen?.category,
      ),
    );
  }

  Future<void> _handleAutoRecord() => _runWorkflow(
        errorPrefix: 'Could not record this violation',
        successMessage: 'Minor violation recorded on the student.',
        action: () => widget.onAutoRecordCase?.call(selectedCase!.id),
        update: (c) => c.copyWith(status: 'Resolved'),
        closesCase: true,
      );

  Future<void> _handleEscalate() async {
    final target = selectedCase;
    if (target == null || _resolving) return;
    final dark = _isDark;
    final theme = _pageTheme;
    // The shared popup (brand-blue primary, secondary Cancel pill), like every
    // other confirmation in the app.
    final confirmed = await showAppPopup<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: theme,
        child: AppPopup(
          title: 'Start an investigation?',
          width: 460,
          isDarkMode: dark,
          body: Text(
            '${target.studentName}\'s case "${target.violationType}" becomes '
            'an investigation. Schedule meetings and file findings under '
            'Investigations, then sanction it.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppPopupColors(dark).text,
            ),
          ),
          actions: [
            AppPopupSecondaryButton(
              label: 'Cancel',
              isDarkMode: dark,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppPopupPrimaryButton(
              key: const Key('escalate-confirm'),
              label: 'Start',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runWorkflow(
      errorPrefix: 'Could not start the investigation',
      successMessage: 'Investigation started.',
      action: () => widget.onEscalateCase?.call(target.id),
      update: (c) => c.copyWith(status: 'Under_Investigation', isEscalated: true),
    );
  }

  Future<void> _handleSanction() async {
    final current = selectedCase;
    if (current == null || _resolving) return;
    final theme = _pageTheme;
    final result = await showAppPopup<SanctionFormResult>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: SanctionDialog(caseItem: current),
      ),
    );
    if (result == null || !mounted) return;
    await _runWorkflow(
      errorPrefix: 'Could not record the sanction',
      successMessage: result.affectsEnrollment
          ? 'Sanction recorded. Re-enrollment is now blocked for this student.'
          : 'Sanction recorded.',
      action: () => widget.onSanctionCase?.call(current.id, result),
      update: (c) => c.copyWith(status: 'Resolved'),
      closesCase: true,
    );
  }

  /// Unlike Validate/Delete, Modify doesn't resolve the case — it opens an
  /// edit screen so the officer can correct the offense, escalation flag,
  /// and penalty notes in place. The case stays in `pendingQueue`; only its
  /// fields change.
  Future<void> _handleModify() async {
    final current = selectedCase;
    if (current == null) return;

    // showDialog inserts its subtree into the root Navigator's Overlay, a
    // sibling of this page's own local Theme — not a descendant of it — so
    // context.isDarkMode inside the dialog would otherwise see the app's
    // ambient theme instead of this dashboard's actual toggle. This State's
    // own `context` is above that local Theme too, so `Theme.of(context)`
    // would capture the ambient (light) one: use the page's own theme.
    final theme = _pageTheme;
    final updated = await showDialog<DisciplineCaseModel>(
      context: context,
      builder: (dialogContext) => Theme(
        data: theme,
        child: _ModifyViolationDialog(
          caseItem: current,
          offenseOptions: _offenseOptions,
        ),
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
        _updateHistory(updated.id, (c) => updated.copyWith(status: c.status));
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
  /// (`onArchiveCase`), pulling it from the active queue immediately. It
  /// stays under "View Archived" until the officer restores, validates or
  /// permanently deletes it there.
  Future<void> _handleDelete() async {
    final target = selectedCase;
    if (target == null || _resolving) return;

    // Colors come from the dashboard's own dark toggle, not this State's
    // `context` (which is above the page's Theme; see _handleModify above).
    final dark = _isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoFormDialog(
        title: 'Delete Violation Report?',
        isDarkMode: dark,
        content: Text(
          '"${target.violationType}" for ${target.studentName} will be '
          'moved to the archive. You can restore it from "View Archived".',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _DashboardColors.secondaryTextFor(dark),
          ),
        ),
        backgroundColor: _DashboardColors.cardFor(dark),
        borderColor: _DashboardColors.cardBorderFor(dark),
        titleColor: _DashboardColors.primaryTextFor(dark),
        cancelFillColor: _DashboardColors.surfaceBackgroundFor(dark),
        confirmColor: const Color(0xFFCD4855),
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        confirmLabel: 'Delete',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resolving = true);
    try {
      await widget.onArchiveCase?.call(target.id);
      if (!mounted) return;
      setState(() {
        pendingQueue.removeWhere((c) => c.id == target.id);
        // An archived ("deleted") report leaves the history too.
        violationHistory.removeWhere((c) => c.id == target.id);
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
    // Renders through the root navigator's overlay, outside this page's own
    // Theme — so its colors are resolved here from the dashboard's own toggle
    // (this State's `context` is above the page's Theme, so it would read the
    // app theme) and the page's theme is re-applied inside.
    final dark = _isDark;
    showResponsiveSheet<void>(
      context: context,
      backgroundColor: _DashboardColors.cardFor(dark),
      handleColor: _DashboardColors.secondaryTextFor(dark),
      desktopMaxWidth: 520,
      builder: (_) => Theme(
        data: _pageTheme,
        child: _ArchivedViolationsSheet(
          loadArchived: loader,
          onRestore: widget.onRestoreArchived,
          onDelete: widget.onDeleteArchivedViolations,
        ),
      ),
    );
  }

  Future<void> _handleGenerateCertificate() async {
    final selected = goodMoralController.selectedStudentRequest;
    if (selected == null) return;

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

  /// Whether the dashboard's own toggle is on dark.
  bool get _isDark => _themeMode.value == ThemeMode.dark;

  /// The Theme [build] wraps this page in. This State's own `context` sits
  /// ABOVE that Theme, so `Theme.of(context)` / `context.isDarkMode` in a
  /// State method read the app's theme instead — anything these methods open
  /// on the root overlay (dialogs, sheets, pushed pages) must take its Theme
  /// and colours from here (see [_DashboardColors]'s `...For(dark)` forms).
  ThemeData get _pageTheme => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _DashboardColors.headerBackground,
        brightness: _isDark ? Brightness.dark : Brightness.light,
      ).withPoppins();

  /// `ProfileScreen` is pushed onto the app's root `Navigator`, so its
  /// subtree lands outside this page's own local `Theme` (the same
  /// Overlay-escapes-local-Theme issue as the header popovers) — wrap it in
  /// a `Theme` matching the current toggle so its `context.isDarkMode`
  /// reads correctly instead of always seeing the app's ambient theme.
  Widget _themedProfileScreen() {
    return Theme(data: _pageTheme, child: const ProfileScreen());
  }

  /// Clicking the header logo acts as a "home" link — back to this
  /// dashboard's own default tab, dismissing "View all notifications"
  /// the same way picking a real tab already does.
  void _goHome() {
    setState(() => _mailboxView = null);
    tabController.selectViolations();
  }

  void _openProfile() {
    _showHeaderPopover(
      cardWidth: 260,
      anchorAboveBottomNav: true,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          userName: widget.officerName,
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

  /// Opening a notification's details marks that one read — here at once, and
  /// saved through the host when [onMarkNotificationRead] is supplied.
  Future<void> _markNotificationRead(String id) async {
    final index = notifications.indexWhere((n) => n.id == id);
    if (index == -1 || notifications[index].isRead) return;
    setState(() {
      notifications = [
        for (final n in notifications)
          n.id == id ? n.copyWith(isRead: true) : n,
      ];
    });
    try {
      await widget.onMarkNotificationRead?.call(id);
    } catch (e) {
      debugPrint('Could not mark notification read: $e');
    }
  }

  void _showNotificationsMenu() {
    _showHeaderPopover(
      cardWidth: 400,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: notifications,
          onOpenNotification: (n) {
            _markNotificationRead(n.id);
            setPopoverState(() {});
          },
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return Theme(
          data: _pageTheme,
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
      actions: [
        if (!isMobile) ...[
          HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            badgeCount: notifications.where((n) => !n.isRead).length,
            onTap: _showNotificationsMenu,
          ),
          const SizedBox(width: 4),
          ProfileAvatarButton(onTap: _openProfile),
        ],
      ],
    );

    // Pinned directly under the header as a part of it; never scrolls.
    final navBar = ValueListenableBuilder<DashboardTab>(
      valueListenable: tabController,
      builder: (context, activeTab, _) => DashboardHeaderNavBar(
        activeTab: activeTab,
        onTabSelected: (tab) {
          setState(() => _mailboxView = null);
          tabController.value = tab;
        },
        onOpenAnalysis: widget.onOpenAnalysis,
      ),
    );

    // Main content shares the same 1440px-capped, centered frame every
    // dashboard module uses (see DashboardPageWrapper).
    final pageContent = DashboardPageWrapper(
      // Matches student_portal_module's StudentPortalSpacing.pageHorizontal:
      // 16px on mobile (not flush with the screen edge), 24px on desktop.
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 16,
      ),
      child: ValueListenableBuilder<DashboardTab>(
        valueListenable: tabController,
        builder: (context, activeTab, _) {
          // Content-sized tabs (and stacked layouts) scroll as a whole;
          // side-by-side master-detail tabs fill the window instead (see
          // _fillsViewport).
          final body = _buildBody(context, activeTab, isMobile: isMobile);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_fillsViewport(context, activeTab))
                Expanded(child: body)
              else
                body,
            ],
          );
        },
      ),
    );

    return Scaffold(
      backgroundColor: _DashboardColors.surfaceBackground(context),
      bottomNavigationBar: isMobile
          ? AppBottomNavBar(
              onNotificationTap: _showNotificationsMenu,
              onProfileTap: _openProfile,
              notificationBadgeCount:
                  notifications.where((n) => !n.isRead).length,
              isDarkMode: isDarkMode,
            )
          : null,
      // The header and sub-nav bar stay fixed at the top; only the tab
      // content below them scrolls, so a short viewport never clips tab
      // content with no way to reach the rest of it.
      body: Column(
        children: [
          header,
          navBar,
          Expanded(
            child: ValueListenableBuilder<DashboardTab>(
              valueListenable: tabController,
              builder: (context, activeTab, _) => DashboardPageScrollView(
                fill: _fillsViewport(context, activeTab),
                child: pageContent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Side-by-side master-detail tabs (Violations, Good Moral, Parental Intervention) fill the
  /// window exactly (no scroll) and only scroll below
  /// kDashboardMinFillHeight; stacked layouts, the placeholder tab, the
  /// mailbox and the skeleton keep their natural, content-sized height.
  bool _fillsViewport(BuildContext context, DashboardTab activeTab) =>
      _mailboxView == null &&
      !widget.isLoading &&
      activeTab != DashboardTab.violationHistory &&
      activeTab != DashboardTab.concerns &&
      activeTab != DashboardTab.investigations &&
      context.showsMasterDetailRow();

  /// [context] is the one from INSIDE the page's own Theme (the caller's
  /// Builder), not the State's bare `context`, which sits above it — so the
  /// loading skeleton follows the dark-mode toggle.
  Widget _buildBody(BuildContext context, DashboardTab activeTab,
      {required bool isMobile}) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: notifications,
          onOpenNotification: (n) => _markNotificationRead(n.id),
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case null:
        if (widget.isLoading && activeTab != DashboardTab.parentalIntervention) {
          return DashboardSkeletonScreen(
            useScaffold: false,
            wrapInPageFrame: false,
            backgroundColor: DisciplineOfficerColors.background(context),
            cardColor: DisciplineOfficerColors.card(context),
            cardBorderColor: DisciplineOfficerColors.cardBorder(context),
            placeholderColor: DisciplineOfficerColors.gray(context),
          );
        }
        return _buildTabContent(activeTab, isMobile: isMobile);
    }
  }

  Widget _buildTabContent(DashboardTab activeTab, {required bool isMobile}) {
    return switch (activeTab) {
      DashboardTab.violations => _buildViolationsContent(isMobile: isMobile),
      DashboardTab.violationHistory =>
        ViolationHistoryView(cases: violationHistory),
      DashboardTab.goodMoral => _buildGoodMoralContent(isMobile: isMobile),
      DashboardTab.parentalIntervention => EndorsementsView(
          reports: widget.escalationReports ?? const [],
          cases: violationHistory,
          loadStudents: widget.onLoadEndorsementStudents ?? _demoEndorsementStudents,
          onIssue: widget.onIssueEscalation,
        ),
      DashboardTab.investigations => InvestigationsView(
          investigations: widget.investigations ?? const [],
          onSchedule: widget.onScheduleMeeting,
          onSetMeetingOutcome: widget.onSetMeetingOutcome,
          onComplete: widget.onCompleteInvestigation,
          onLoadEvidence: widget.onLoadInvestigationEvidence,
        ),
      DashboardTab.concerns => Builder(
          builder: (tabContext) => ConcernsView(
            concerns: widget.studentConcerns ?? const [],
            onUpdate: widget.onUpdateConcern,
            endorsedConcernIds: {
              // A declined endorsement frees its concern to be endorsed again.
              for (final r in widget.escalationReports ?? const <EscalationReportModel>[])
                if (r.concernId != null && r.status != 'Rejected') r.concernId!,
            },
            onEndorse: widget.onIssueEscalation == null
                ? null
                : (concern) => _endorseConcern(tabContext, concern),
          ),
        ),
    };
  }

  /// Opens the Endorse popup for a concern's student, filled in from what the
  /// student wrote, and sends the endorsement tied to that concern.
  Future<void> _endorseConcern(
    BuildContext tabContext,
    ConcernReportModel concern,
  ) async {
    final draft = await showEndorseDialog(
      tabContext,
      cases: violationHistory,
      // A migrated classmate report is about the classmate: endorse them.
      studentNumber: concern.aboutStudentNumber ?? concern.studentNumber,
      studentName: concern.aboutStudentName ?? concern.studentName,
      concernId: concern.id,
      initialSummary: '${concern.concernLabel}: ${concern.details}',
    );
    if (draft == null || !tabContext.mounted) return;
    final messenger = ScaffoldMessenger.of(tabContext);
    try {
      await widget.onIssueEscalation!(draft);
      messenger.showSnackBar(const SnackBar(
        content: Text('Endorsement sent to the Guidance Associate.'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not send the endorsement: $e')));
    }
  }

  /// Demo / offline source for the Endorsements tab: the student list the page
  /// was given, filtered by name or number.
  Future<EndorsementStudentPage> _demoEndorsementStudents({
    required int page,
    String query = '',
  }) async {
    final needle = query.trim().toLowerCase();
    final all = [
      for (final s in widget.initialStudentDirectory ?? const <StudentDirectoryEntryModel>[])
        if (needle.isEmpty ||
            s.studentName.toLowerCase().contains(needle) ||
            s.studentNumber.toLowerCase().contains(needle))
          s,
    ];
    final from = (page - 1) * kEndorsementPageSize;
    return (
      items: all.skip(from).take(kEndorsementPageSize).toList(),
      totalCount: all.length,
    );
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
      onModify: _handleModify,
      onDelete: _handleDelete,
      onClassify: _handleClassify,
      onAutoRecord: _handleAutoRecord,
      onEscalate: _handleEscalate,
      onSanction: _handleSanction,
      evidenceUrls: _evidenceUrls,
      onLoadHistory: widget.onLoadCaseHistory,
    );

    // Mobile and stacked layouts put the stat cards first, above the queue;
    // on desktop they move into the Preview panel's column (see below).
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

        if (stackColumns) {
          return Column(
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

        // The stat cards sit above the Preview panel (squeezed into its
        // column) rather than spanning the full width above everything, so
        // the queue card can run all the way up to the sub-nav bar — same
        // as the Professor Dashboard's Conduct Report tab. The Preview
        // panel becomes the flexible child, filling the rest of the
        // column's height, only when an ancestor (the master-detail Row
        // below) actually gives this column a bounded height to fill.
        final detailsColumn = LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                statsRow,
                const SizedBox(height: 18),
                bounded ? Expanded(child: detailsPanel) : detailsPanel,
              ],
            );
          },
        );

        // Master-detail: the queue "sidebar" is height-locked to match the
        // details column (CrossAxisAlignment.stretch), capped so the pair
        // never grows past ~one viewport — the queue's own list, and the
        // Preview panel, scroll internally within that fixed height instead.
        return MasterDetailRowFrame(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: queueCard),
              const SizedBox(width: 18),
              Expanded(child: detailsColumn),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGoodMoralContent({required bool isMobile}) {
    return GoodMoralManagementView(
      controller: goodMoralController,
      onGenerateCertificate: _handleGenerateCertificate,
      onFlagRequest: widget.onFlagGoodMoralRequest,
      onUseRegistrarRecord: widget.onUseRegistrarRecordGoodMoral,
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
// Top-level header navigation bar (Violations / Good Moral /
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
    this.onOpenAnalysis,
  });

  final DashboardTab activeTab;
  final ValueChanged<DashboardTab> onTabSelected;

  /// Not a tab of this dashboard: it opens the analysis workspace.
  final VoidCallback? onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    // Full-bleed strip pinned directly under the main header (see
    // DashboardSubNavStrip).
    return DashboardSubNavStrip(
      backgroundColor: _DashboardColors.navBarBackground(context),
      borderColor: _DashboardColors.cardBorder(context),
      child: Row(
        // Stretch so every _DashboardNavBarItem spans the bar's full 48px
        // height, letting its indicator's Positioned(bottom: 0) land flush
        // on the strip's own bottom edge instead of being inset by the
        // row's own vertical centering.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardNavBarItem(
            label: 'Violations',
            icon: Icons.assignment_late_outlined,
            isActive: activeTab == DashboardTab.violations,
            onTap: () => onTabSelected(DashboardTab.violations),
          ),
          const SizedBox(width: 32),
          _DashboardNavBarItem(
            label: 'Students Violation History',
            icon: Icons.history_rounded,
            isActive: activeTab == DashboardTab.violationHistory,
            onTap: () => onTabSelected(DashboardTab.violationHistory),
          ),
          const SizedBox(width: 32),
          _DashboardNavBarItem(
            label: 'Good Moral',
            icon: Icons.verified_outlined,
            isActive: activeTab == DashboardTab.goodMoral,
            onTap: () => onTabSelected(DashboardTab.goodMoral),
          ),
          const SizedBox(width: 32),
          _DashboardNavBarItem(
            label: 'Endorsements',
            icon: Icons.family_restroom_outlined,
            isActive: activeTab == DashboardTab.parentalIntervention,
            onTap: () => onTabSelected(DashboardTab.parentalIntervention),
          ),
          const SizedBox(width: 32),
          _DashboardNavBarItem(
            label: 'Concerns',
            icon: Icons.volunteer_activism_outlined,
            isActive: activeTab == DashboardTab.concerns,
            onTap: () => onTabSelected(DashboardTab.concerns),
          ),
          const SizedBox(width: 32),
          _DashboardNavBarItem(
            label: 'Investigations',
            icon: Icons.manage_search_rounded,
            isActive: activeTab == DashboardTab.investigations,
            onTap: () => onTabSelected(DashboardTab.investigations),
          ),
          if (onOpenAnalysis != null) ...[
            const SizedBox(width: 32),
            _DashboardNavBarItem(
              label: 'Analysis',
              icon: Icons.query_stats_outlined,
              isActive: false,
              onTap: onOpenAnalysis!,
            ),
          ],
        ],
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
  Widget build(BuildContext context) => NavHoverUnderline(
        isActive: isActive,
        color: subNavActiveColor(context, _DashboardColors.navBarIndicator),
        child: _tab(context),
      );

  Widget _tab(BuildContext context) {
    final color = isActive
        ? subNavActiveColor(context, _DashboardColors.navBarActiveText)
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
                    ? subNavActiveColor(context, _DashboardColors.navBarIndicator)
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

/// "Profile Settings / Dark Mode / Sign Out" dropdown opened from the
/// header's avatar button (Figma node 488:1105) — narrower and plainer
/// than [HeaderPopoverCard] (used by Notifications/Settings), so it builds
/// its own card chrome instead of reusing that shell. Shared verbatim by
/// every dashboard module except Admin (which has no such menu) and the
/// Student Portal (uses this same widget, but from its own header rather
/// than a staff `AppHeaderNavBar`).
class AccountProfileMenu extends StatelessWidget {
  const AccountProfileMenu({
    super.key,
    required this.userName,
    required this.onViewProfile,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.onLogout,
  });

  /// Shown in the header row above the menu items. No email/plan-badge row
  /// (unlike some reference designs) — nothing in this app tracks a
  /// signed-in user's email or a subscription tier to show there.
  final String userName;

  final VoidCallback onViewProfile;

  /// Current theme state — flips the "Dark Mode" row's label/icon to
  /// "Light Mode" once dark mode is active.
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
    final borderColor =
        isDarkMode ? const Color(0x0D334155) : const Color(0x0D000000);
    final textColor = isDarkMode ? const Color(0xFFF5F5F5) : Colors.black;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 260,
        child: BentoCard(
          backgroundColor: isDarkMode ? const Color(0xFF191A1F) : Colors.white,
          borderColor: borderColor,
          clipBehavior: Clip.antiAlias,
          isDarkMode: isDarkMode,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDarkMode
                            ? const Color(0xFF22242B)
                            : const Color(0xFFF0F5F8),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 22,
                        color: isDarkMode
                            ? Colors.white70
                            : const Color(0xFF15253F),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: borderColor),
              _AccountMenuItem(
                icon: Icons.settings_outlined,
                label: 'Profile Settings',
                onTap: onViewProfile,
                isDarkMode: isDarkMode,
              ),
              _AccountMenuItem(
                icon: isDarkMode
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: isDarkMode ? 'Light Mode' : 'Dark Mode',
                onTap: onToggleDarkMode,
                isDarkMode: isDarkMode,
              ),
              // The notification sound: one switch, the same on every
              // dashboard, kept across sign-out and restart.
              ValueListenableBuilder<bool>(
                valueListenable: NotificationSoundSettings.enabled,
                builder: (context, soundOn, _) => _AccountMenuItem(
                  key: const Key('notification-sound-toggle'),
                  icon: soundOn
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  label: 'Notification Sound',
                  onTap: NotificationSoundSettings.toggle,
                  isDarkMode: isDarkMode,
                  trailing: _SoundSwitch(on: soundOn, isDarkMode: isDarkMode),
                ),
              ),
              Divider(height: 1, color: borderColor),
              _AccountMenuItem(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                onTap: onLogout,
                isDarkMode: isDarkMode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The on/off pill at the end of the "Notification Sound" row. Not itself
/// tappable — the whole row is — so it just shows the state.
class _SoundSwitch extends StatelessWidget {
  const _SoundSwitch({required this.on, required this.isDarkMode});

  final bool on;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final accent = isDarkMode ? kSubNavActiveDarkColor : const Color(0xFF345892);
    final off = isDarkMode ? const Color(0xFF3F3F46) : const Color(0xFFCBD5E1);
    return AnimatedContainer(
      key: Key(on ? 'sound-switch-on' : 'sound-switch-off'),
      duration: const Duration(milliseconds: 150),
      width: 36,
      height: 20,
      padding: const EdgeInsets.all(2),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: on ? accent : off,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on && isDarkMode ? const Color(0xFF191A1F) : Colors.white,
        ),
      ),
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDarkMode,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDarkMode;

  /// Something at the row's far end (the sound switch).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkMode ? const Color(0xFFF5F5F5) : Colors.black87;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Popup opened by the Violation Queue's "View Archived" button — every
/// archived report, whether manually deleted or auto-expired after 72 hours
/// open. Each card offers Restore (back to the queue) and nothing else.
/// Nothing here is purged automatically. Laid out like the system's other
/// popups: a title and close button, a short note, then rounded cards (a
/// bottom sheet on phones, a dialog on wide screens).
class _ArchivedViolationsSheet extends StatefulWidget {
  const _ArchivedViolationsSheet({
    required this.loadArchived,
    this.onRestore,
    this.onDelete,
  });

  final Future<List<DisciplineCaseModel>> Function() loadArchived;
  final Future<void> Function(String caseId)? onRestore;

  /// Permanently deletes archived reports by id. No search-select-delete
  /// controls when omitted (demo mode — nothing is stored).
  final Future<void> Function(List<String> caseIds)? onDelete;

  @override
  State<_ArchivedViolationsSheet> createState() =>
      _ArchivedViolationsSheetState();
}

class _ArchivedViolationsSheetState extends State<_ArchivedViolationsSheet> {
  /// Reports per page. Each card is tall (name, violation, status, Restore),
  /// so five is what fits the popup without scrolling; the shared footer
  /// then pages through the rest.
  static const _pageSize = 5;

  List<DisciplineCaseModel>? _items;
  Object? _error;
  final Set<String> _busy = {};
  int _page = 1;

  final _searchController = TextEditingController();
  String _query = '';

  /// Ids ticked for "Delete selected" — always a subset of what is listed.
  final Set<String> _selected = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The archived reports matching the search bar.
  List<DisciplineCaseModel> get _visible {
    final items = _items ?? const <DisciplineCaseModel>[];
    if (_query.trim().isEmpty) return items;
    return [
      for (final c in items)
        if (archiveMatchesQuery(_query, [
          c.studentName,
          c.studentNumber,
          c.violationType,
          c.status?.replaceAll('_', ' '),
          c.expiredAt != null ? 'expired' : 'deleted',
        ]))
          c,
    ];
  }

  void _onSearchChanged(String value) => setState(() {
        _query = value;
        _page = 1;
        // Only rows you can still see stay ticked.
        final visibleIds = _visible.map((c) => c.id).toSet();
        _selected.retainWhere(visibleIds.contains);
      });

  void _toggleSelected(String id, bool on) =>
      setState(() => on ? _selected.add(id) : _selected.remove(id));

  void _toggleAll(bool on) => setState(() {
        _selected.clear();
        if (on) _selected.addAll(_visible.map((c) => c.id));
      });

  /// Confirms, then permanently deletes [targets] from the archive.
  Future<void> _deleteReports(List<DisciplineCaseModel> targets) async {
    final onDelete = widget.onDelete;
    if (onDelete == null || targets.isEmpty || _deleting) return;
    final what = archiveCountLabel(targets.length, 'archived report');
    final confirmed = await confirmArchiveDelete(
      context,
      title: 'Delete selected reports?',
      message: 'This permanently deletes $what. They cannot be restored '
          'afterwards.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    final ids = [for (final c in targets) c.id];
    setState(() => _deleting = true);
    try {
      await onDelete(ids);
      if (!mounted) return;
      setState(() {
        _items?.removeWhere((c) => ids.contains(c.id));
        _selected.removeAll(ids);
      });
      _toast('${archiveCountLabel(ids.length, 'report')} deleted.');
    } catch (e) {
      _toast('Could not delete: $e');
      // Show what is really left (some may have gone through).
      _selected.clear();
      await _reload();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _reload() async {
    try {
      final items = await widget.loadArchived();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [action] for [item], then drops it from the list and shows
  /// [success], or the error if it fails.
  Future<void> _run(
    DisciplineCaseModel item,
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _busy.add(item.id));
    try {
      await action();
      if (!mounted) return;
      setState(() {
        final items = _items;
        if (items != null) {
          final i = items.indexWhere((c) => c.id == item.id);
          if (i != -1) items.removeAt(i);
        }
      });
      _toast(success);
    } catch (e) {
      _toast('Action failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.78;
    final all = _items;
    final items = all == null ? null : _visible;

    // Paged client-side over the searched list. The page is clamped, not
    // stored as-is: restoring the last report of the last page must land on
    // the new last page, not on one that no longer exists.
    final totalPages = items == null || items.isEmpty
        ? 1
        : (items.length / _pageSize).ceil();
    final page = _page.clamp(1, totalPages);
    Widget? footer;

    Widget body;
    if (_error != null) {
      body = _ArchivedMessage(
        icon: Icons.error_outline_rounded,
        title: 'Could not load archived reports',
        detail: '$_error',
      );
    } else if (items == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    } else if (all!.isEmpty) {
      body = const _ArchivedMessage(
        icon: Icons.archive_outlined,
        title: 'No archived reports',
        detail: 'Reports you delete, or that stay open past 72 hours, '
            'appear here.',
      );
    } else if (items.isEmpty) {
      body = const _ArchivedMessage(
        icon: Icons.search_off_rounded,
        title: 'No matching reports',
        detail: 'Try a different name, student number or violation.',
      );
    } else {
      final pageItems =
          items.skip((page - 1) * _pageSize).take(_pageSize).toList();
      footer = Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
        child: CardPaginationFooter(
          currentPage: page,
          totalPages: totalPages,
          totalCount: items.length,
          textColor: _DashboardColors.secondaryText(context),
          accentColor: DisciplineOfficerColors.azureBlue,
          mutedBackground: _DashboardColors.surfaceBackground(context),
          onPrevious: () => setState(() => _page = page - 1),
          onNext: () => setState(() => _page = page + 1),
        ),
      );
      body = ListView.separated(
        // A new key per page so the next page opens at its top.
        key: ValueKey('archived-page-$page'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        itemCount: pageItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = pageItems[index];
          final busy = _busy.contains(item.id);
          return _ArchivedReportCard(
            key: ValueKey('archived-${item.id}'),
            item: item,
            busy: busy || _deleting,
            selected: _selected.contains(item.id),
            onSelectedChanged: widget.onDelete == null
                ? null
                : (on) => _toggleSelected(item.id, on),
            onRestore: widget.onRestore == null
                ? null
                : () => _run(item, () => widget.onRestore!(item.id),
                    success: 'Report restored to the queue.'),
          );
        },
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: AppPopupHeader(
                title: 'Archived Violation Reports',
                subtitle: 'Deleted reports and reports left open for over '
                    '72 hours. Restore them to the queue here.',
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            if (all != null && all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: ArchiveToolbar(
                  searchController: _searchController,
                  onSearchChanged: _onSearchChanged,
                  searchHint: 'Search name, student number or violation',
                  visibleCount: items?.length ?? 0,
                  selectedCount: _selected.length,
                  busy: _deleting,
                  fillColor: _DashboardColors.surfaceBackground(context),
                  onToggleAll: widget.onDelete == null ? null : _toggleAll,
                  onDeleteSelected: widget.onDelete == null
                      ? null
                      : () => _deleteReports([
                            for (final c in all)
                              if (_selected.contains(c.id)) c,
                          ]),
                ),
              ),
            Divider(height: 1, color: _DashboardColors.cardBorder(context)),
            Flexible(child: body),
            if (footer != null) ...[
              Divider(height: 1, color: _DashboardColors.cardBorder(context)),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}

/// One archived report: who it was filed against, what for, why it is
/// archived, and its one action, Restore.
class _ArchivedReportCard extends StatelessWidget {
  const _ArchivedReportCard({
    super.key,
    required this.item,
    required this.busy,
    this.selected = false,
    this.onSelectedChanged,
    this.onRestore,
  });

  final DisciplineCaseModel item;
  final bool busy;
  final bool selected;

  /// Null hides the tick-box (nothing can be deleted from this archive).
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final text = _DashboardColors.primaryText(context);
    final muted = _DashboardColors.secondaryText(context);
    final expired = item.expiredAt != null;
    final badgeColor =
        expired ? const Color(0xFFD97706) : const Color(0xFF64748B);
    final archivedAt = item.archivedAt;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DashboardColors.surfaceBackground(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onSelectedChanged != null) ...[
                ArchiveCheckbox(
                  key: Key('archived-select-${item.id}'),
                  value: selected,
                  onChanged: busy ? null : onSelectedChanged,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.studentName,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    Text(
                      item.studentNumber,
                      style: GoogleFonts.poppins(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  expired ? 'Expired (72h)' : 'Deleted',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.violationType,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: text,
            ),
          ),
          if (archivedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '${expired ? 'Expired' : 'Archived'} ${formatDateTime12h(archivedAt)}'
              '${item.status == null ? '' : ' · ${item.status!.replaceAll('_', ' ')}'}',
              style: GoogleFonts.poppins(fontSize: 12, color: muted),
            ),
          ],
          if (onRestore != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('archived-restore'),
              onPressed: busy ? null : onRestore,
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: Text(
                'Restore',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The archive popup's empty / error state: a muted icon, a title and a line
/// of detail, centered.
class _ArchivedMessage extends StatelessWidget {
  const _ArchivedMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final muted = _DashboardColors.secondaryText(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 44),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _DashboardColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12, height: 1.45, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Broad severity bucket an [OffenseOption] falls into, used to power the
/// Minor/Major filter in the offense picker sheet. Prefers [OffenseOption
/// .category] (`handbook_offenses.category`, e.g. "Minor"/"Major_A") when
/// present; falls back to sniffing the "Minor – "/"Major – " prefix baked
/// into the built-in demo labels, so the filter still works with no real
/// data wired up.
enum _OffenseTier { minor, major }

_OffenseTier _tierOf(OffenseOption option) {
  final basis = option.category ?? option.label;
  return basis.toLowerCase().startsWith('minor')
      ? _OffenseTier.minor
      : _OffenseTier.major;
}

/// Sub-heading an [OffenseOption] is grouped under in the picker sheet —
/// the exact `category` when known (so Major_A/B/C/D each get their own
/// group), otherwise just its [_OffenseTier] name.
String _groupLabelOf(OffenseOption option) {
  final category = option.category;
  if (category != null && category.isNotEmpty) return category;
  return _tierOf(option) == _OffenseTier.minor ? 'Minor' : 'Major';
}

/// The offense picker sheet's severity filter — All shows every offense
/// (still grouped per category); Minor/Major narrow it to one [_OffenseTier].
enum _OffenseFilter {
  all,
  minor,
  major;

  bool matches(OffenseOption option) {
    switch (this) {
      case _OffenseFilter.all:
        return true;
      case _OffenseFilter.minor:
        return _tierOf(option) == _OffenseTier.minor;
      case _OffenseFilter.major:
        return _tierOf(option) == _OffenseTier.major;
    }
  }
}

/// One segment of the All/Minor/Major filter atop the offense picker —
/// Sized to match [PaginationPillButton] (the Previous/Next paging
/// buttons) — same 12/6 padding and 12px/w600 label — instead of the
/// Delete/Modify/Validate action buttons' bulkier 33px height.
class _TierFilterButton extends StatelessWidget {
  const _TierFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _DashboardColors.navBarActiveText
          : _DashboardColors.surfaceBackground(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : _DashboardColors.primaryText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small label rendered above a field — matches "Report a Technical
/// Issue"'s `_ReportFieldLabel` shape/typography instead of a Material
/// floating `labelText` inside the field's own border.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _DashboardColors.primaryText(context),
        ),
      ),
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

  /// Pale, borderless, rounded-10 field fill — matches the "Report a
  /// Technical Issue" dialog's field shape (see
  /// `report_technical_issue_dialog.dart`'s `_fieldDecoration`) instead of
  /// this dialog's old default Material outlined-box-with-floating-label.
  InputDecoration _fieldDecoration(BuildContext context, {String? hintText}) {
    final borderless = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.poppins(
        fontSize: 13,
        color: _DashboardColors.secondaryText(context),
      ),
      isDense: true,
      filled: true,
      fillColor: _DashboardColors.surfaceBackground(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: borderless,
      enabledBorder: borderless,
      disabledBorder: borderless,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
            color: _DashboardColors.navBarActiveText, width: 1.5),
      ),
    );
  }

  void _save() {
    final offenseId = _selectedOffenseId;
    final selectedOffense =
        widget.offenseOptions.where((o) => o.id == offenseId).firstOrNull;
    final offenseLabel = selectedOffense?.label;

    Navigator.of(context).pop(
      widget.caseItem.copyWith(
        offenseId: offenseId,
        violationType: offenseLabel ?? widget.caseItem.violationType,
        offenseCategory: selectedOffense?.category,
        isEscalated: _isEscalated,
        penaltyImposed: _penaltyController.text.trim(),
      ),
    );
  }

  /// Replaces the plain native dropdown with a sheet listing offenses
  /// grouped by category (Minor, Major_A, Major_B, …), with an All/Minor
  /// /Major filter up top to cut the list down to one severity tier at a
  /// time — the full flat list is unwieldy once `handbook_offenses` has
  /// more than a handful of rows.
  Future<void> _pickOffense(BuildContext context) async {
    final sheetSurface = _DashboardColors.card(context);
    final sheetText = _DashboardColors.primaryText(context);
    final sheetDark = context.isDarkMode;
    final sheetMuted = _DashboardColors.secondaryText(context);

    final currentId = _selectedOffenseId;
    final currentOption =
        widget.offenseOptions.where((o) => o.id == currentId).firstOrNull;
    var filter = currentOption != null
        ? (_tierOf(currentOption) == _OffenseTier.minor
            ? _OffenseFilter.minor
            : _OffenseFilter.major)
        : _OffenseFilter.minor;

    final choice = await showResponsiveSheet<String>(
      context: context,
      backgroundColor: sheetSurface,
      handleColor: sheetMuted,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.7;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final visible =
                widget.offenseOptions.where(filter.matches).toList();
            final grouped = <String, List<OffenseOption>>{};
            for (final option in visible) {
              grouped.putIfAbsent(_groupLabelOf(option), () => []).add(option);
            }

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: AppPopupHeader(
                        title: 'Select Offense',
                        isDarkMode: sheetDark,
                        onClose: () => Navigator.of(sheetContext).pop(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _TierFilterButton(
                            label: 'All',
                            selected: filter == _OffenseFilter.all,
                            onTap: () => setSheetState(
                                () => filter = _OffenseFilter.all),
                          ),
                          const SizedBox(width: 10),
                          _TierFilterButton(
                            label: 'Minor',
                            selected: filter == _OffenseFilter.minor,
                            onTap: () => setSheetState(
                                () => filter = _OffenseFilter.minor),
                          ),
                          const SizedBox(width: 10),
                          _TierFilterButton(
                            label: 'Major',
                            selected: filter == _OffenseFilter.major,
                            onTap: () => setSheetState(
                                () => filter = _OffenseFilter.major),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: grouped.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No offenses in this category.',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: sheetMuted,
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final entry in grouped.entries) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 14, 12, 6),
                                      child: FilterLabelBand(
                                        label: entry.key,
                                        surface: sheetSurface,
                                      ),
                                    ),
                                    for (final option in entry.value)
                                      ListTile(
                                        title: Text(
                                          option.label,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: sheetText,
                                          ),
                                        ),
                                        trailing: option.id == _selectedOffenseId
                                            ? const Icon(
                                                Icons.check_rounded,
                                                color: _DashboardColors
                                                    .navBarActiveText,
                                              )
                                            : null,
                                        onTap: () => Navigator.of(sheetContext)
                                            .pop(option.id),
                                      ),
                                  ],
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (choice != null) setState(() => _selectedOffenseId = choice);
  }

  @override
  Widget build(BuildContext context) {
    // BentoFormDialog is this app's shared shell for every "Rename X" /
    // "Delete X" style form dialog (see this same file's archive-delete
    // confirmation) — this one previously hand-rolled its own Dialog +
    // BentoCard with a bespoke close (X) icon and 18px title, which drifted
    // from that shared shape/typography. Switching to it here matches the
    // 16px title, 13px Poppins buttons, and BentoCard padding every other
    // dialog in the app already uses.
    return BentoFormDialog(
      title: 'Modify Violation',
      backgroundColor: _DashboardColors.card(context),
      borderColor: _DashboardColors.cardBorder(context),
      titleColor: _DashboardColors.primaryText(context),
      cancelFillColor: _DashboardColors.surfaceBackground(context),
      cancelLabel: 'Cancel',
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: 'Save Changes',
      onConfirm: _save,
      content: SingleChildScrollView(
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
            const _FieldLabel(label: 'Offense'),
            Builder(
              builder: (fieldContext) {
                final selected = widget.offenseOptions
                    .where((o) => o.id == _selectedOffenseId)
                    .firstOrNull;
                return InkWell(
                  onTap: () => _pickOffense(fieldContext),
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: _fieldDecoration(fieldContext),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected?.label ?? 'Select an offense',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: selected == null
                                  ? _DashboardColors.secondaryText(fieldContext)
                                  : _DashboardColors.primaryText(fieldContext),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: _DashboardColors.secondaryText(fieldContext),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const _FieldLabel(label: "Officer's Notes / Penalty"),
            TextFormField(
              controller: _penaltyController,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: _DashboardColors.primaryText(context),
              ),
              decoration: _fieldDecoration(context),
              minLines: 3,
              maxLines: 5,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Shown separately from the original report notes on the case preview.',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: _DashboardColors.secondaryText(context),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Escalate to Security',
                style: GoogleFonts.poppins(
                  color: _DashboardColors.primaryText(context),
                ),
              ),
              value: _isEscalated,
              onChanged: (value) => setState(() => _isEscalated = value),
            ),
          ],
        ),
      ),
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
    this.onFlagRequest,
    this.onUseRegistrarRecord,
    this.studentDirectoryPage = 1,
    this.studentDirectoryTotalPages = 1,
    this.studentDirectoryTotalCount,
    this.studentDirectoryLoading = false,
    this.onStudentDirectoryPageChanged,
    this.isMobile = false,
  });

  final GoodMoralDashboardController controller;
  final VoidCallback onGenerateCertificate;
  final Future<void> Function(
    GoodMoralSelectedStudent request,
    String note,
    bool sendBack,
  )? onFlagRequest;
  final Future<void> Function(GoodMoralSelectedStudent request)?
      onUseRegistrarRecord;

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
          onFlagRequest: onFlagRequest,
          onUseRegistrarRecord: onUseRegistrarRecord,
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

            return MasterDetailRowFrame(
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
  Widget build(BuildContext context) => CardPaginationFooter(
        currentPage: currentPage,
        totalPages: totalPages,
        totalCount: totalCount,
        isLoading: isLoading,
        textColor: _DashboardColors.secondaryText(context),
        accentColor: DisciplineOfficerColors.azureBlue,
        mutedBackground: DisciplineOfficerColors.background(context),
        onPrevious: onPrevious,
        onNext: onNext,
      );
}

// Notifications dropdown moved to widgets/notifications_popover.dart —
// shared verbatim with every other module.
