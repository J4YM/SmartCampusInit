import 'dart:async';

import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:student_portal_module/student_portal_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auto_refresh.dart';
import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../data/notifications_repository.dart';
import '../data/student_portal_repository.dart';
import '../env.dart';

/// Wires the presentation-only [StudentPortalHomePage] to Supabase
/// (violations, attendance, schedule — see [StudentPortalRepository]). Falls back to
/// the page's own built-in mock data when Supabase isn't configured or the
/// signed-in account is a static demo account (id not a real UUID), same
/// convention every other connected page in this codebase follows.
class StudentPortalConnectedPage extends StatefulWidget {
  const StudentPortalConnectedPage({
    super.key,
    this.currentUser,
    this.onReturnToHub,
    this.onSignOut,
  });

  final AppUser? currentUser;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<StudentPortalConnectedPage> createState() =>
      _StudentPortalConnectedPageState();
}

class _StudentPortalConnectedPageState
    extends State<StudentPortalConnectedPage> with AutoRefreshMixin {
  List<StudentViolationModel>? _violations;
  List<AttendanceEntry>? _attendance;
  List<StudentScheduleEntryModel>? _schedule;
  List<GoodMoralRequestStatus>? _goodMoralRequests;
  List<ReferralRequestStatus>? _referrals;
  StudentRiskSnapshot? _risk;

  /// "BS Information Technology · 4th Year · Section 4A" from the student's
  /// own row; null until read (the page then shows a neutral placeholder).
  String? _programLine;

  /// The student's own notifications (the shared `notifications` table, role
  /// Student, addressed to them). Null until read — and for a demo account,
  /// which keeps the page's built-in sample messages.
  List<StudentNotificationModel>? _notifications;
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  static const _demoProgramLine = 'BS Information Technology · 3rd Year · Section A';

  StudentPortalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentPortalRepository(Supabase.instance.client);
  }

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  /// `null` for static demo accounts (ids like "u_student" aren't real
  /// UUIDs and have no backing `students`/`profiles` row) — same guard
  /// `GuidanceCounselorConnectedPage._notifiableUserId` already uses.
  String? get _studentId {
    final user = widget.currentUser;
    if (user == null || user.role != AppRole.student) return null;
    if (user.id.startsWith('u_')) return null;
    return user.id;
  }

  @override
  void initState() {
    super.initState();
    _load();
    // `_load` is already quiet (no spinner, errors swallowed), so the same
    // call keeps violations, attendance, schedule and requests current.
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

  /// Reads this student's notifications. Going through
  /// [NotificationsRepository.fetchForRole] is also what makes a newly sent
  /// one ring the notification sound (see `NotificationAlert`).
  Future<void> _loadNotifications() async {
    final repo = _notifRepo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;
    try {
      final items = await repo.fetchForRole(AppRole.student, userId: studentId);
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
    if (!AppEnv.supabaseConfigured || _studentId == null) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:student')
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
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    await _loadNotifications();

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
      final line = await repo.fetchProgramLine(studentId);
      if (mounted && line != null) setState(() => _programLine = line);
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
      final referrals = await repo.fetchMyReferrals(studentId);
      if (mounted) setState(() => _referrals = referrals);
    } catch (_) {}

    try {
      final risk = await repo.fetchLatestRisk(studentId);
      if (mounted) setState(() => _risk = risk);
    } catch (_) {}
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
        requestedBy: widget.currentUser?.displayName ?? 'Student',
        remarks: remarks,
      );

      final requests = await repo.fetchMyGoodMoralRequests(studentId);
      if (mounted) setState(() => _goodMoralRequests = requests);
      _toast('Document request submitted.');
    } catch (e) {
      _toast('Could not submit your request: $e');
    }
  }

  Future<void> _submitReferral({
    required ReferralConcern concern,
    required String details,
    String? aboutStudentNumber,
    required bool urgent,
  }) async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    try {
      await repo.submitReferral(
        studentId: studentId,
        concern: concern,
        details: details,
        aboutStudentNumber: aboutStudentNumber,
        urgent: urgent,
      );
      final referrals = await repo.fetchMyReferrals(studentId);
      if (mounted) setState(() => _referrals = referrals);
      _toast('Referral sent to the Guidance Office.');
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not send your referral: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudentPortalHomePage(
      studentName: widget.currentUser?.displayName ?? 'Demo Student',
      onSignOut: widget.onSignOut,
      onReturnToHub: widget.onReturnToHub,
      programLine: _programLine ?? (_studentId == null ? _demoProgramLine : ''),
      // A real student never sees the page's sample data while the reads are
      // in flight; a demo account keeps it.
      initialViolations: _violations ?? (_studentId == null ? null : const []),
      initialAttendance: _attendance ?? (_studentId == null ? null : const []),
      initialSchedule: _schedule ?? (_studentId == null ? null : const []),
      // A real student sees only their own notifications (never the sample
      // ones while the read is in flight); a demo account keeps the samples.
      initialNotifications:
          _notifications ?? (_studentId == null ? null : const []),
      onMarkNotificationRead: _studentId == null || _notifRepo == null
          ? null
          : (id) => _notifRepo!.markRead(id),
      onMarkAllNotificationsRead: _studentId == null || _notifRepo == null
          ? null
          : () => _notifRepo!
              .markAllReadForRole(AppRole.student, userId: _studentId),
      initialGoodMoralRequests: _goodMoralRequests,
      onSubmitGoodMoralRequest: _submitGoodMoralRequest,
      initialReferrals: _referrals,
      onSubmitReferral: _submitReferral,
      riskSnapshot: _risk,
    );
  }
}
