import 'package:flutter/material.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../auth/app_user.dart';
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
    extends State<ParentPortalConnectedPage> {
  List<StudentViolationModel>? _violations;
  List<AttendanceEntry>? _attendance;
  List<StudentScheduleEntryModel>? _schedule;
  List<GoodMoralRequestStatus>? _goodMoralRequests;
  List<InterventionMessageModel>? _interventions;
  ({String name, String programLine, String? studentNumber})? _child;

  ParentPortalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return ParentPortalRepository(Supabase.instance.client);
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
  }

  Future<void> _load() async {
    final repo = _repo;
    final parentId = _parentId;
    if (repo == null || parentId == null) return;

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
