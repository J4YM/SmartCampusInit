import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart'
    show GoodMoralFormData, GuidanceMeetingInvite;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auto_refresh.dart';
import '../app/notification_alert.dart';
import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../data/guidance_investigation_repository.dart';
import '../data/notifications_repository.dart';
import '../data/parent_credential_repository.dart';
import '../data/parent_portal_repository.dart';
import '../env.dart';
import 'parent_change_password_dialog.dart';

/// Wires the presentation-only [ParentPortalHomePage] to Supabase
/// (violations, attendance, schedule — see [ParentPortalRepository]). Falls back to
/// the page's own built-in mock data when Supabase isn't configured or the
/// signed-in account is a static demo account (id not a real UUID), same
/// convention every other connected page in this codebase follows.
class ParentPortalConnectedPage extends StatefulWidget {
  const ParentPortalConnectedPage({
    super.key,
    this.currentUser,
    this.onReturnToHub,
    this.onSignOut,
  });

  final AppUser? currentUser;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<ParentPortalConnectedPage> createState() =>
      _ParentPortalConnectedPageState();
}

class _ParentPortalConnectedPageState
    extends State<ParentPortalConnectedPage> with AutoRefreshMixin {
  List<StudentViolationModel>? _violations;
  List<AttendanceEntry>? _attendance;
  List<StudentScheduleEntryModel>? _schedule;
  List<GoodMoralRequestStatus>? _goodMoralRequests;
  GoodMoralFormData? _goodMoralPrefill;
  bool _goodMoralPrefillFailed = false;
  List<InterventionMessageModel>? _interventions;
  List<GuidanceMeetingInvite>? _meetings;
  ({String name, String programLine, String? studentNumber})? _child;

  /// The parent's own notifications (the shared `notifications` table, role
  /// Parent, addressed to them). Null until read — and for a demo account,
  /// which keeps the page's built-in sample messages.
  List<StudentNotificationModel>? _notifications;
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  ParentPortalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return ParentPortalRepository(Supabase.instance.client);
  }

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  /// The signed-in parent's own `profiles.id` — `null` for static demo
  /// accounts (ids like "u_parent" aren't real UUIDs and have no backing
  /// `profiles` row) and for anyone who isn't a parent, same guard
  /// `GuidanceCounselorConnectedPage._notifiableUserId` already uses.
  String? get _parentId {
    final user = widget.currentUser;
    if (user == null || user.role != AppRole.parent) return null;
    if (user.id.startsWith('u_')) return null;
    return user.id;
  }

  /// The linked child's `students.id` (see
  /// [ParentPortalRepository.fetchLinkedStudentId]), resolved once in
  /// [_load]. Everything below is keyed by it exactly as the Student Portal
  /// keys by the student's own id.
  String? _studentId;

  /// Every child this parent is linked to (`students.id` -> banner details),
  /// in link order — what the child switcher lists.
  final Map<String, ({String name, String programLine, String? studentNumber})>
      _roster = {};
  List<String> _rosterOrder = const [];

  bool get _isDemo => _repo == null || _parentId == null;

  @override
  void initState() {
    super.initState();
    _load();
    // `_load` is already quiet (no spinner, errors swallowed), so the same
    // call keeps the child's violations, attendance and messages current.
    startAutoRefresh(_load, interval: const Duration(seconds: 45));
    _subscribeToNotificationChanges();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requirePasswordChangeIfDue());
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  /// Reads this parent's notifications. Going through
  /// [NotificationsRepository.fetchForRole] is also what makes a newly sent
  /// one ring the notification sound (see `NotificationAlert`).
  Future<void> _loadNotifications() async {
    final repo = _notifRepo;
    final parentId = _parentId;
    if (repo == null || parentId == null) return;
    try {
      final items = await repo.fetchForRole(AppRole.parent, userId: parentId);
      if (!mounted) return;
      setState(() => _notifications = [
            for (final n in items) _toPortalNotification(n),
          ]);
    } catch (_) {
      // Keeps what is on screen; the next poll or push tries again.
    }
  }

  /// A new notification lands without waiting for the 45s poll. Needs
  /// `notifications` in the `supabase_realtime` publication (see
  /// supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured || _parentId == null) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:parent')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            _reloadDebounce?.cancel();
            _reloadDebounce =
                Timer(const Duration(milliseconds: 400), _loadNotifications);
          },
        )
        .subscribe();
  }

  StudentNotificationModel _toPortalNotification(NotificationItemModel n) =>
      StudentNotificationModel(
        id: n.id,
        senderName: 'STI Baliuag',
        senderRole: NotificationSenderRole.system,
        title: n.title,
        message: n.message,
        timestamp: n.timestamp,
        isRead: n.isRead,
      );

  /// True once the child this load was started for is no longer the one on
  /// screen (the guardian switched children mid-load) — a stale result must
  /// never be painted over the new child's data.
  bool _isStale(String studentId) => !mounted || _studentId != studentId;

  /// Blocks the portal behind a "choose your own password" step while this
  /// guardian is still on the temporary password the registrar issued (a
  /// Microsoft parent has no credential row, so this never fires for them).
  Future<void> _requirePasswordChangeIfDue() async {
    final parentId = _parentId;
    if (parentId == null || !AppEnv.supabaseConfigured) return;
    final credentials = ParentCredentialRepository(Supabase.instance.client);
    try {
      final login = await credentials.session(parentId);
      if (login == null || !login.mustChangePassword || !mounted) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ParentChangePasswordDialog(
          repository: credentials,
          parentId: parentId,
          onSignOut: widget.onSignOut,
        ),
      );
    } catch (_) {
      // Migration not installed: no credential to rotate.
    }
  }

  Future<void> _selectChild(String studentId) async {
    if (studentId == _studentId) return;
    setState(() {
      _studentId = studentId;
      _child = _roster[studentId];
      _violations = null;
      _attendance = null;
      _schedule = null;
      _goodMoralRequests = null;
      _goodMoralPrefill = null;
      _goodMoralPrefillFailed = false;
      _interventions = null;
    });
    await _load();
  }

  Future<void> _load() async {
    final repo = _repo;
    final parentId = _parentId;
    if (repo == null || parentId == null) return;

    await _loadNotifications();

    // Only students `parent_student_links` maps to THIS parent are ever
    // listed or fetched — there is no way to address another family's child.
    List<String> linkedIds = const [];
    try {
      linkedIds = await repo.fetchLinkedStudentIds(parentId);
    } catch (_) {
      // Falls back to the page's own mock data, same as the fetches below.
    }
    if (linkedIds.isEmpty || !mounted) return;

    for (final id in linkedIds) {
      if (_roster.containsKey(id)) continue;
      try {
        final profile = await repo.fetchStudentProfile(id);
        if (profile != null) _roster[id] = profile;
      } catch (_) {}
    }
    if (!mounted) return;
    _rosterOrder = linkedIds;

    final studentId =
        linkedIds.contains(_studentId) ? _studentId! : linkedIds.first;
    setState(() {
      _studentId = studentId;
      _child = _roster[studentId];
    });

    try {
      final violations = await repo.fetchViolations(studentId);
      if (!_isStale(studentId)) setState(() => _violations = violations);
    } catch (_) {
      // Falls back to the page's own mock data — no error state needed for
      // a read-only preview; matches this repo's convention elsewhere.
    }

    try {
      final studentRow = await Supabase.instance.client
          .from('students')
          .select('section_id')
          .eq('id', studentId)
          .maybeSingle();
      final sectionId = studentRow?['section_id'] as String?;
      // Only the attendance fetch below depends on sectionId — the
      // schedule and Good Moral requests fetches further down don't, so a
      // null section must not skip them (a `return` here would exit the
      // whole `_load()` method, not just this block).
      if (sectionId != null) {
        final now = DateTime.now();
        final attendance = await repo.fetchAttendance(
          studentId,
          sectionId,
          from: now.subtract(const Duration(days: 90)),
          to: now,
        );
        if (!_isStale(studentId)) setState(() => _attendance = attendance);
      }
    } catch (_) {}

    try {
      final schedule = await repo.fetchSchedule(studentId);
      if (!_isStale(studentId)) setState(() => _schedule = schedule);
    } catch (_) {}

    try {
      final goodMoralRequests = await repo.fetchMyGoodMoralRequests(studentId);
      if (!_isStale(studentId)) {
        setState(() => _goodMoralRequests = goodMoralRequests);
      }
    } catch (_) {}
    try {
      final prefill = await repo.fetchGoodMoralPrefill(studentId);
      if (!_isStale(studentId)) {
        setState(() {
          _goodMoralPrefill = prefill;
          _goodMoralPrefillFailed = prefill == null;
        });
      }
    } catch (_) {
      if (!_isStale(studentId)) setState(() => _goodMoralPrefillFailed = true);
    }

    try {
      final interventions = await repo.fetchInterventions(studentId);
      // The school's messages to this parent are their other notification
      // feed: a new unread one rings the notification sound too.
      NotificationAlert.observe('ParentMessages|$parentId', [
        for (final m in interventions)
          NotificationItemModel(
            id: m.id,
            title: m.title,
            message: m.message,
            timestamp: m.createdAt,
            isRead: m.isRead,
          ),
      ]);
      if (!_isStale(studentId)) setState(() => _interventions = interventions);
    } catch (_) {
      // Table not created yet / not readable: the card keeps its empty or
      // demo state.
    }

    await _loadMeetings(studentId);
  }

  /// Guidance meetings this parent is invited to (RLS limits the rows to
  /// their own child and to meetings that invite a parent).
  Future<void> _loadMeetings(String studentId) async {
    if (!AppEnv.supabaseConfigured || _parentId == null) return;
    try {
      final meetings = await GuidanceInvestigationRepository(
              Supabase.instance.client)
          .fetchMeetingsForStudent(studentId);
      if (!_isStale(studentId)) {
        setState(() => _meetings = [
              for (final m in meetings)
                GuidanceMeetingInvite(
                  id: m.id,
                  scheduledAt: m.scheduledAt,
                  status: m.status.value,
                  location: m.location,
                  responseNote: m.responseNote,
                ),
            ]);
      }
    } catch (_) {
      // Guidance tables not migrated yet: the card stays hidden.
    }
  }

  Future<void> _respondToMeeting(
    GuidanceMeetingInvite meeting,
    bool accept,
    String? note,
  ) async {
    await GuidanceInvestigationRepository(Supabase.instance.client)
        .respond(meeting.id, accept: accept, note: note);
    final studentId = _studentId;
    if (studentId != null) await _loadMeetings(studentId);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitGoodMoralRequest({
    required String documentType,
    required String purpose,
    String? remarks,
    required Map<String, dynamic> formData,
  }) async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    try {
      await repo.submitGoodMoralRequest(
        studentId: studentId,
        documentType: documentType,
        purpose: purpose,
        requestedBy: widget.currentUser?.displayName ?? 'Parent',
        remarks: remarks,
        formData: formData,
      );

      final requests = await repo.fetchMyGoodMoralRequests(studentId);
      if (mounted) setState(() => _goodMoralRequests = requests);
      _toast('Document request submitted.');
    } catch (e) {
      _toast('Could not submit your request: $e');
    }
  }

  Future<void> _resubmitGoodMoralRequest({
    required String requestId,
    required String purpose,
    String? remarks,
    required Map<String, dynamic> formData,
  }) async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    try {
      await repo.resubmitGoodMoralRequest(
        requestId: requestId,
        purpose: purpose,
        remarks: remarks,
        formData: formData,
      );
      final requests = await repo.fetchMyGoodMoralRequests(studentId);
      if (mounted) setState(() => _goodMoralRequests = requests);
      _toast('Request resubmitted to the Discipline Office.');
    } catch (e) {
      _toast('Could not resubmit your request: $e');
    }
  }

  /// Child picker shown only when this guardian has more than one linked
  /// student. Lists exactly the parent's own children — that is the mapping.
  Widget _buildChildSwitcher(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Icon(Icons.family_restroom_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Your children:',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                for (final id in _rosterOrder)
                  if (_roster[id] != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_roster[id]!.name),
                        selected: id == _studentId,
                        onSelected: (_) => _selectChild(id),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _buildPortal();
    final children = [
      for (final id in _rosterOrder)
        if (_roster[id] != null) id,
    ];
    if (children.length < 2) return page;
    return Column(
      children: [
        _buildChildSwitcher(context),
        // Keyed by the child so the portal's own state (tabs, scroll,
        // locally-held lists) restarts cleanly for each one.
        Expanded(child: KeyedSubtree(key: ValueKey(_studentId), child: page)),
      ],
    );
  }

  Widget _buildPortal() {
    return ParentPortalHomePage(
      parentName: widget.currentUser?.displayName ?? 'Demo Parent',
      // Demo accounts (no Supabase / static ids) keep the page's own mock
      // child; a real parent sees a neutral placeholder until the fetch lands.
      studentName: _child?.name ?? (_isDemo ? 'Juan Dela Cruz' : 'Your child'),
      programLine: _child?.programLine ??
          (_isDemo ? 'BS Information Technology · 3rd Year · BSIT-3A' : ''),
      studentNumber: _child?.studentNumber,
      onSignOut: widget.onSignOut,
      onReturnToHub: widget.onReturnToHub,
      initialViolations: _violations,
      initialAttendance: _attendance,
      initialSchedule: _schedule,
      initialGoodMoralRequests: _goodMoralRequests,
      goodMoralPrefill: _goodMoralPrefill,
      goodMoralPrefillFailed: _goodMoralPrefillFailed,
      // A real parent sees only their own notifications (never the sample
      // ones while the read is in flight); a demo account keeps the samples.
      initialNotifications:
          _notifications ?? (_parentId == null ? null : const []),
      onMarkNotificationRead: _parentId == null || _notifRepo == null
          ? null
          : (id) => _notifRepo!.markRead(id),
      onMarkAllNotificationsRead: _parentId == null || _notifRepo == null
          ? null
          : () => _notifRepo!
              .markAllReadForRole(AppRole.parent, userId: _parentId),
      // A real parent never sees demo messages while the fetch is in flight.
      initialInterventions: _interventions ?? (_isDemo ? null : const []),
      onInterventionRead: (id) async {
        try {
          await _repo?.markInterventionRead(id);
        } catch (_) {}
      },
      onSubmitGoodMoralRequest: _submitGoodMoralRequest,
      onResubmitGoodMoralRequest: _resubmitGoodMoralRequest,
      initialMeetings: _meetings,
      onRespondMeeting: _isDemo ? null : _respondToMeeting,
    );
  }
}
