import 'dart:async';

import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auto_refresh.dart';
import '../app/notification_alert.dart';
import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../data/notifications_repository.dart';
import '../data/parent_portal_repository.dart';
import '../env.dart';

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
  List<InterventionMessageModel>? _interventions;
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

  bool get _isDemo => _repo == null || _parentId == null;

  @override
  void initState() {
    super.initState();
    _load();
    // `_load` is already quiet (no spinner, errors swallowed), so the same
    // call keeps the child's violations, attendance and messages current.
    startAutoRefresh(_load, interval: const Duration(seconds: 45));
    _subscribeToNotificationChanges();
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

  Future<void> _load() async {
    final repo = _repo;
    final parentId = _parentId;
    if (repo == null || parentId == null) return;

    await _loadNotifications();

    String? studentId;
    try {
      studentId = await repo.fetchLinkedStudentId(parentId);
    } catch (_) {
      // Falls back to the page's own mock data, same as the fetches below.
    }
    if (studentId == null || !mounted) return;
    _studentId = studentId;

    try {
      final child = await repo.fetchStudentProfile(studentId);
      if (mounted && child != null) setState(() => _child = child);
    } catch (_) {}

    try {
      final violations = await repo.fetchViolations(studentId);
      if (mounted) setState(() => _violations = violations);
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
        if (mounted) setState(() => _attendance = attendance);
      }
    } catch (_) {}

    try {
      final schedule = await repo.fetchSchedule(studentId);
      if (mounted) setState(() => _schedule = schedule);
    } catch (_) {}

    try {
      final goodMoralRequests = await repo.fetchMyGoodMoralRequests(studentId);
      if (mounted) setState(() => _goodMoralRequests = goodMoralRequests);
    } catch (_) {}

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
      if (mounted) setState(() => _interventions = interventions);
    } catch (_) {
      // Table not created yet / not readable: the card keeps its empty or
      // demo state.
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitGoodMoralRequest({
    required String documentType,
    required String purpose,
    String? remarks,
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
      );

      final requests = await repo.fetchMyGoodMoralRequests(studentId);
      if (mounted) setState(() => _goodMoralRequests = requests);
      _toast('Document request submitted.');
    } catch (e) {
      _toast('Could not submit your request: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
    );
  }
}
