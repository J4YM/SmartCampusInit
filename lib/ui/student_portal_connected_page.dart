import 'package:flutter/material.dart';
import 'package:student_portal_module/student_portal_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../auth/app_user.dart';
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
    extends State<StudentPortalConnectedPage> {
  List<StudentViolationModel>? _violations;
  List<AttendanceEntry>? _attendance;
  List<StudentScheduleEntryModel>? _schedule;
  List<GoodMoralRequestStatus>? _goodMoralRequests;

  StudentPortalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentPortalRepository(Supabase.instance.client);
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
  }

  Future<void> _load() async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

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

  @override
  Widget build(BuildContext context) {
    return StudentPortalHomePage(
      studentName: widget.currentUser?.displayName ?? 'Demo Student',
      onSignOut: widget.onSignOut,
      onReturnToHub: widget.onReturnToHub,
      initialViolations: _violations,
      initialAttendance: _attendance,
      initialSchedule: _schedule,
      initialGoodMoralRequests: _goodMoralRequests,
      onSubmitGoodMoralRequest: _submitGoodMoralRequest,
    );
  }
}
