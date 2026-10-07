import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../data/audit_logger.dart';
import '../data/discipline_repository.dart';
import '../data/escalation_repository.dart';
import '../data/notifications_repository.dart';
import '../documents/document_preview_page.dart';
import '../documents/good_moral_certificate_text.dart';
import '../env.dart';

/// Rows per server page of the Good Moral Student List, given the app-wide
/// card density ([cardPageSize], 5 on a phone): a phone keeps that density so
/// the list isn't 25 rows long, a wider screen loads 25 at a time.
int studentDirectoryPageSizeFor(int cardPageSize) => cardPageSize < 10
    ? cardPageSize
    : _DisciplineOfficerConnectedPageState._studentDirectoryDesktopPageSize;

/// Wires the presentation-only [DisciplineOfficerDashboardPage] to Supabase
/// via [DisciplineRepository] — active violations, Good Moral requests, the
/// student directory, and summary metrics all come from real tables; Modify
/// and Validate/Deny persist back to `student_violations`.
///
/// Falls back to the page's own built-in mock data when Supabase isn't
/// configured (`AppEnv.supabaseConfigured` is false), so this still renders
/// something reasonable in that case rather than an empty/broken screen.
class DisciplineOfficerConnectedPage extends StatefulWidget {
  const DisciplineOfficerConnectedPage({
    super.key,
    this.officerName,
    this.currentUser,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? officerName;

  /// The signed-in user — used to attribute audit log entries (see
  /// [AuditLogger]) to whoever actually performed the action.
  final AppUser? currentUser;

  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<DisciplineOfficerConnectedPage> createState() =>
      _DisciplineOfficerConnectedPageState();
}

class _DisciplineOfficerConnectedPageState
    extends State<DisciplineOfficerConnectedPage> {
  bool _loading = true;
  String? _error;

  /// Rows per page of the Good Moral Student List on a wide screen. On a phone
  /// it follows the app-wide card density instead (5, like every other list).
  static const _studentDirectoryDesktopPageSize = 25;

  int get _studentDirectoryPageSize =>
      studentDirectoryPageSizeFor(context.cardPageSize);

  /// The page size the loaded student directory was actually fetched with —
  /// what the page's own pagination must count by, even if the window has
  /// since been resized across the phone breakpoint.
  int? _loadedStudentPageSize;
  bool _resizingStudentDirectory = false;

  DisciplineSummaryMetricsModel? _metrics;
  List<DisciplineCaseModel>? _pendingQueue;
  List<DisciplineCaseModel>? _violationHistory;
  List<GoodMoralRequestModel>? _goodMoralRequests;
  List<StudentDirectoryEntryModel>? _studentDirectory;
  int? _studentDirectoryTotalCount;
  List<OffenseOption>? _offenseOptions;
  List<NotificationItemModel>? _notifications;
  List<EscalationReportModel>? _escalationReports;

  RealtimeChannel? _violationsChannel;
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  DisciplineRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
  }

  EscalationRepository? get _escalationRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return EscalationRepository(Supabase.instance.client);
  }

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  AuditLogger? get _auditLogger {
    final user = widget.currentUser;
    if (!AppEnv.supabaseConfigured || user == null) return null;
    return AuditLogger(
      Supabase.instance.client,
      actorId: user.id.startsWith('u_') ? null : user.id,
      actorEmail: user.username,
      actorRole: user.role,
    );
  }

  /// A real Supabase Auth id safe to filter `notifications.user_id` (a uuid
  /// column) by — `null` for the static demo accounts
  /// (lib/auth/static_demo_accounts.dart), whose ids like "u_officer" aren't
  /// valid UUIDs and have no real `profiles` row to match anyway (same
  /// fallback [_auditLogger] already uses for `actorId`).
  String? get _notifiableUserId {
    final id = widget.currentUser?.id;
    if (id == null || id.startsWith('u_')) return null;
    return id;
  }

  /// [silent] skips the full-screen loading spinner — used for realtime-
  /// triggered reloads so a change elsewhere (e.g. a kiosk submission)
  /// refreshes the queue in place instead of flashing the whole dashboard
  /// back to a spinner.
  Future<void> _load({bool silent = false}) async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final violations = await repo.fetchActiveViolations();
      final history = await repo.fetchViolationHistory();
      final counts = await repo.fetchStatusCounts();
      final studentPageSize = _studentDirectoryPageSize;
      final studentPage = await repo.fetchStudentDirectoryPage(
        page: 1,
        pageSize: studentPageSize,
      );
      final offenses = await repo.fetchOffenseOptions();
      List<EscalationReportModel>? reports;
      try {
        reports = await _escalationRepo?.fetchReports();
      } catch (e) {
        // Escalation tables may not be migrated yet; the rest of the
        // dashboard must still load.
        debugPrint('Could not load escalation reports: $e');
      }
      final notifications = await _notifRepo?.fetchForRole(
        AppRole.disciplineOfficer,
        userId: _notifiableUserId,
      );

      if (!mounted) return;
      setState(() {
        _pendingQueue = violations;
        _violationHistory = history;
        _metrics = DisciplineSummaryMetricsModel(
          pendingQueueCount: counts.activeTotal,
          escalatedCount: counts.escalatedActive,
          processedTodayCount: counts.resolvedToday,
          avgResponseTimeMinutes: counts.avgResolutionMinutes,
        );
        _studentDirectory = studentPage.items;
        _studentDirectoryTotalCount = studentPage.totalCount;
        _loadedStudentPageSize = studentPageSize;
        _offenseOptions = offenses;
        if (reports != null) _escalationReports = reports;
        if (notifications != null) _notifications = notifications;
      });
      await _loadGoodMoralRequests();
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        // A transient background-refresh failure shouldn't kick the officer
        // out to the full error screen away from data they can already see.
        debugPrint('Could not silently refresh discipline data: $e');
      } else {
        setState(() => _error = 'Could not load discipline data: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fetches Good Moral requests and updates [_goodMoralRequests] — pulled
  /// out of [_load] so [_generateCertificate] can re-run just this fetch
  /// after marking a request Fulfilled, without reloading everything else.
  Future<void> _loadGoodMoralRequests() async {
    final repo = _repo;
    if (repo == null) return;
    final goodMoral = await repo.fetchGoodMoralRequests();
    if (mounted) setState(() => _goodMoralRequests = goodMoral);
  }

  Future<List<StudentDirectoryEntryModel>> _loadStudentDirectoryPage(int page) async {
    final repo = _repo;
    if (repo == null) return const [];
    final result = await repo.fetchStudentDirectoryPage(
      page: page,
      pageSize: _loadedStudentPageSize ?? _studentDirectoryPageSize,
    );
    if (mounted) setState(() => _studentDirectoryTotalCount = result.totalCount);
    return result.items;
  }

  /// The window was resized across the phone breakpoint (or rotated): refetch
  /// the Student List's first page at the new size, so a phone never keeps
  /// showing a 25-row page. Swaps the rows and the size in one setState so the
  /// page's pagination never counts a page by the wrong size.
  void _syncStudentDirectoryPageSize() {
    final loaded = _loadedStudentPageSize;
    if (_studentDirectory == null || loaded == null) return;
    if (_resizingStudentDirectory || loaded == _studentDirectoryPageSize) return;
    _resizingStudentDirectory = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = _repo;
      final size = _studentDirectoryPageSize;
      try {
        if (repo == null || !mounted) return;
        final page =
            await repo.fetchStudentDirectoryPage(page: 1, pageSize: size);
        if (!mounted) return;
        setState(() {
          _studentDirectory = page.items;
          _studentDirectoryTotalCount = page.totalCount;
          _loadedStudentPageSize = size;
        });
      } catch (e) {
        debugPrint('Could not resize the student directory page: $e');
        _loadedStudentPageSize = size; // don't retry on every rebuild
      } finally {
        _resizingStudentDirectory = false;
      }
    });
  }

  Future<void> _resolveCase(String caseId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.resolveViolation(caseId);
    await _auditLogger?.log(action: 'Validated violation report', recordId: caseId);
  }

  Future<void> _modifyCase(
    String caseId, {
    String? offenseId,
    bool? isEscalated,
    String? penaltyImposed,
  }) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.updateViolation(
      caseId,
      offenseId: offenseId,
      isEscalated: isEscalated,
      penaltyImposed: penaltyImposed,
    );
    await _auditLogger?.log(action: 'Modified violation report', recordId: caseId);
  }

  Future<void> _archiveCase(String caseId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.archiveViolation(caseId);
    await _auditLogger?.log(
      action: 'Archived (deleted) violation report',
      recordId: caseId,
      severity: 'WARN',
    );
  }

  Future<void> _issueEscalation(EscalationDraft draft) async {
    final repo = _escalationRepo;
    if (repo == null) return;
    await repo.issue(
      draft,
      officerId: _notifiableUserId,
      officerName: widget.currentUser?.displayName ?? widget.officerName,
    );
    await _auditLogger?.log(
      action: 'Issued escalation report for ${draft.studentNumber}',
    );
    final reports = await repo.fetchReports();
    if (mounted) setState(() => _escalationReports = reports);
  }

  Future<void> _restoreArchived(String caseId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.restoreViolation(caseId);
    await _auditLogger?.log(action: 'Restored archived violation report', recordId: caseId);
    await _load(silent: true);
  }

  Future<void> _validateArchived(String caseId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.validateArchivedViolation(caseId);
    await _auditLogger?.log(action: 'Validated archived violation report', recordId: caseId);
    await _load(silent: true);
  }

  Future<void> _deleteArchivedPermanently(String caseId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.deleteViolationPermanently(caseId);
    await _auditLogger?.log(
      action: 'Permanently deleted archived violation report',
      recordId: caseId,
      severity: 'WARN',
    );
    await _load(silent: true);
  }

  Future<List<DisciplineCaseModel>> _loadArchivedViolations() async {
    final repo = _repo;
    if (repo == null) return const [];
    return repo.fetchArchivedViolations();
  }

  Future<void> _markNotificationsRead() async {
    final repo = _notifRepo;
    if (repo == null) return;
    await repo.markAllReadForRole(
      AppRole.disciplineOfficer,
      userId: _notifiableUserId,
    );
  }

  /// Builds a Good Moral Certificate for [selected] and opens it in the
  /// shared preview screen (preview, print, PDF/DOCX download). Matches the
  /// school's verified official format exactly — including stating any
  /// active violation on the record instead of refusing to generate one
  /// (that block now lives only as the Clearance Status banner shown before
  /// generating; see discipline_officer_dashboard_page.dart).
  Future<void> _generateCertificate(GoodMoralSelectedStudent selected) async {
    final now = DateTime.now();
    final logoBytes = (await rootBundle.load('assets/images/sti_logo.png'))
        .buffer
        .asUint8List();

    final paragraphSpans = buildGoodMoralCertificationParagraph(
      studentName: selected.studentName,
      program: selected.program,
      enrollmentYear: selected.enrollmentYear,
      currentYear: now.year,
      activeViolations: selected.activeViolations,
    );

    final document = DocxDocumentBuilder()
        .add(
          DocxImage(
            bytes: logoBytes,
            extension: 'png',
            width: 90,
            height: 90,
            altText: 'STI College seal',
          ),
        )
        .add(
          const DocxParagraph(
            align: DocxAlign.center,
            spacingBefore: 120,
            spacingAfter: 240,
            children: [
              DocxText(
                'CERTIFICATION',
                fontWeight: DocxFontWeight.bold,
                fontSize: 18,
              ),
            ],
          ),
        )
        .add(
          DocxParagraph(
            spacingAfter: 240,
            children: [
              for (final span in paragraphSpans)
                DocxText(
                  span.text,
                  fontWeight:
                      span.bold ? DocxFontWeight.bold : DocxFontWeight.normal,
                ),
            ],
          ),
        )
        .p('${_formatDate(now)}, was issued for educational purposes only.')
        .p('')
        .p('')
        .add(
          DocxParagraph(
            children: [
              DocxText(
                widget.officerName ?? 'Student Affairs and Discipline Officer',
                fontWeight: DocxFontWeight.bold,
              ),
            ],
          ),
        )
        .p('Student Affairs and Discipline Officer')
        .build();

    await _auditLogger?.log(
      action: 'Generated Good Moral Certificate for ${selected.studentName}',
      recordId: selected.studentNumber,
    );

    if (selected.sourceSubTab == GoodMoralSubTab.requests) {
      final repo = _repo;
      if (repo != null) {
        // Best-effort: the certificate has already been built at this point,
        // so a failure marking the request Fulfilled (e.g. Task 7's SQL
        // migration adding `status` hasn't been run yet) must never block
        // delivering it via Navigator.push below.
        try {
          await repo.markGoodMoralRequestFulfilled(selected.sourceId);
          await _loadGoodMoralRequests();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentPreviewPage(
          title: 'Good Moral Certificate — ${selected.studentName}',
          document: document,
          fileBaseName:
              'GoodMoral_${selected.studentName.replaceAll(' ', '_')}',
        ),
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _subscribeToViolationChanges();
    _subscribeToNotificationChanges();
  }

  /// Live-refreshes the bell when a new notification lands for this
  /// dashboard — same debounced-reload pattern as
  /// [_subscribeToViolationChanges]. Requires `notifications` to be in the
  /// `supabase_realtime` publication (see
  /// supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:discipline_officer')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  /// Live-refreshes the Approval Queue when `student_violations` changes —
  /// e.g. a new violation submitted at the Virtual Admission Kiosk, or an
  /// edit from another Discipline Officer — without a manual page reload.
  /// Requires `student_violations` to be added to the `supabase_realtime`
  /// publication (see supabase/add_realtime_publication.sql).
  void _subscribeToViolationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _violationsChannel = Supabase.instance.client
        .channel('public:student_violations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'student_violations',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  /// Debounced so a burst of changes (e.g. the mock-data populate script,
  /// or several kiosk submissions in a row) triggers one reload, not one
  /// per row.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _violationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    final notifChannel = _notificationsChannel;
    if (notifChannel != null) {
      Supabase.instance.client.removeChannel(notifChannel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  textStyle: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Retry'),
              ),
              ],
            ),
          ),
        ),
      );
    }

    final repo = _repo;
    _syncStudentDirectoryPageSize();
    return DisciplineOfficerDashboardPage(
      // Only the very first fetch shows a skeleton (inside the tab content —
      // the header and tabs render right away); later reloads just swap in
      // fresh data.
      isLoading: _loading && _metrics == null,
      officerName: widget.officerName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialMetrics: _metrics,
      initialPendingQueue: _pendingQueue,
      initialViolationHistory: _violationHistory,
      initialGoodMoralRequests: _goodMoralRequests,
      initialStudentDirectory: _studentDirectory,
      studentDirectoryTotalCount: _studentDirectoryTotalCount,
      studentDirectoryPageSize:
          _loadedStudentPageSize ?? _studentDirectoryPageSize,
      onLoadStudentDirectoryPage: repo == null ? null : _loadStudentDirectoryPage,
      availableOffenses: _offenseOptions,
      onResolveCase: repo == null ? null : _resolveCase,
      onModifyCase: repo == null ? null : _modifyCase,
      onArchiveCase: repo == null ? null : _archiveCase,
      onLoadArchivedViolations: repo == null ? null : _loadArchivedViolations,
      onRestoreArchived: repo == null ? null : _restoreArchived,
      onValidateArchived: repo == null ? null : _validateArchived,
      onModifyArchived: repo == null ? null : _modifyCase,
      onDeleteArchived: repo == null ? null : _deleteArchivedPermanently,
      escalationReports: _escalationReports,
      onIssueEscalation: _escalationRepo == null ? null : _issueEscalation,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onGenerateGoodMoralCertificate: _generateCertificate,
    );
  }
}
