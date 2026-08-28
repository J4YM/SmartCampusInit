import 'dart:async';

import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../data/audit_logger.dart';
import '../data/discipline_repository.dart';
import '../data/notifications_repository.dart';
import '../documents/document_letterhead.dart';
import '../documents/document_preview_page.dart';
import '../env.dart';

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

  static const _studentDirectoryPageSize = 25;

  DisciplineSummaryMetricsModel? _metrics;
  List<DisciplineCaseModel>? _pendingQueue;
  List<GoodMoralRequestModel>? _goodMoralRequests;
  List<StudentDirectoryEntryModel>? _studentDirectory;
  int? _studentDirectoryTotalCount;
  List<OffenseOption>? _offenseOptions;
  List<NotificationItemModel>? _notifications;

  RealtimeChannel? _violationsChannel;
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  DisciplineRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
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
      final counts = await repo.fetchStatusCounts();
      final goodMoral = await repo.fetchGoodMoralRequests();
      final studentPage = await repo.fetchStudentDirectoryPage(
        page: 1,
        pageSize: _studentDirectoryPageSize,
      );
      final offenses = await repo.fetchOffenseOptions();
      final notifications = await _notifRepo?.fetchForRole(
        AppRole.disciplineOfficer,
        userId: _notifiableUserId,
      );

      if (!mounted) return;
      setState(() {
        _pendingQueue = violations;
        _metrics = DisciplineSummaryMetricsModel(
          pendingQueueCount: counts.activeTotal,
          escalatedCount: counts.escalatedActive,
          processedTodayCount: counts.resolvedToday,
          avgResponseTimeMinutes: counts.avgResolutionMinutes,
        );
        _goodMoralRequests = goodMoral;
        _studentDirectory = studentPage.items;
        _studentDirectoryTotalCount = studentPage.totalCount;
        _offenseOptions = offenses;
        if (notifications != null) _notifications = notifications;
      });
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

  Future<List<StudentDirectoryEntryModel>> _loadStudentDirectoryPage(int page) async {
    final repo = _repo;
    if (repo == null) return const [];
    final result = await repo.fetchStudentDirectoryPage(
      page: page,
      pageSize: _studentDirectoryPageSize,
    );
    if (mounted) setState(() => _studentDirectoryTotalCount = result.totalCount);
    return result.items;
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
  /// shared preview screen (preview, print, PDF/DOCX download). Only
  /// reached for students the module has already confirmed have no active
  /// violation (see `_handleGenerateCertificate` in
  /// discipline_officer_dashboard_page.dart).
  Future<void> _generateCertificate(GoodMoralSelectedStudent selected) async {
    final now = DateTime.now();
    final purpose = selected.purpose?.trim();
    final requestedBy = selected.requestedBy?.trim();

    final document = addLetterhead(
      DocxDocumentBuilder(),
      documentTitle: 'Certificate of Good Moral Character',
    )
        .p('TO WHOM IT MAY CONCERN:')
        .p(
          'This is to certify that ${selected.studentName}, a bona fide '
          'student of STI College Baliuag under '
          '${selected.programGradeSection}, with student number '
          '${selected.studentNumber}, has not been found guilty of any '
          'offense involving moral turpitude and is, based on the records '
          'of this office as of ${_formatDate(now)}, of good moral '
          'character.',
        )
        .p(
          purpose == null || purpose.isEmpty
              ? 'This certification is issued upon the request of the '
                  'student for whatever legal purpose it may serve.'
              : 'This certification is issued upon the request of '
                  '${requestedBy == null || requestedBy.isEmpty ? 'the student' : requestedBy} '
                  'for $purpose.',
        )
        .p('Issued this ${_formatDate(now)} at Baliuag, Bulacan, Philippines.')
        .p('')
        .p('')
        .p('_____________________________')
        .p(widget.officerName ?? 'Student Affairs & Services')
        .p('Student Affairs & Services')
        .build();

    await _auditLogger?.log(
      action: 'Generated Good Moral Certificate for ${selected.studentName}',
      recordId: selected.studentNumber,
    );

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
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repo = _repo;
    return DisciplineOfficerDashboardPage(
      officerName: widget.officerName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialMetrics: _metrics,
      initialPendingQueue: _pendingQueue,
      initialGoodMoralRequests: _goodMoralRequests,
      initialStudentDirectory: _studentDirectory,
      studentDirectoryTotalCount: _studentDirectoryTotalCount,
      studentDirectoryPageSize: _studentDirectoryPageSize,
      onLoadStudentDirectoryPage: repo == null ? null : _loadStudentDirectoryPage,
      availableOffenses: _offenseOptions,
      onResolveCase: repo == null ? null : _resolveCase,
      onModifyCase: repo == null ? null : _modifyCase,
      onArchiveCase: repo == null ? null : _archiveCase,
      onLoadArchivedViolations: repo == null ? null : _loadArchivedViolations,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onGenerateGoodMoralCertificate: _generateCertificate,
    );
  }
}
