import 'package:flutter/material.dart';
import 'package:professor_module/professor_module.dart';

/// Wires [ProfessorDashboardPage] into the app shell the same way every
/// other dashboard module is wired (see [DisciplineOfficerConnectedPage],
/// [GuidanceCounselorConnectedPage]).
///
/// There's no `class_sections` / `attendance_records` schema in Supabase
/// yet, so unlike those two this page has nothing to fetch — it renders the
/// presentation page directly, which falls back to its own built-in demo
/// data. Once those tables exist, fetch them here in `initState` and pass
/// them down as `initialSections` / `initialStudentAttendance`, mirroring
/// `DisciplineOfficerConnectedPage`.
class ProfessorConnectedPage extends StatelessWidget {
  const ProfessorConnectedPage({
    super.key,
    this.professorName,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? professorName;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return ProfessorDashboardPage(
      professorName: professorName ?? 'Juan Dela Cruz',
      onReturnToHub: onReturnToHub,
      onSignOut: onSignOut,
    );
  }
}
