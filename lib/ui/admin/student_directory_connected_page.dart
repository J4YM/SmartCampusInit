import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/students_repository.dart';
import '../../env.dart';
import '../../models/student_record.dart';
import 'staff_role_mapping.dart' show avatarInitialsFor;

/// Wires the presentation-only [StudentDirectoryPage] (from `admin_dashboard`)
/// to Supabase via [StudentsRepository] — the same repository already used by
/// the RFID Management module (`lib/ui/dashboard_page.dart`), so this shows
/// the same enrolled students already in the database.
class StudentDirectoryConnectedPage extends StatefulWidget {
  const StudentDirectoryConnectedPage({super.key});

  @override
  State<StudentDirectoryConnectedPage> createState() =>
      _StudentDirectoryConnectedPageState();
}

class _StudentDirectoryConnectedPageState
    extends State<StudentDirectoryConnectedPage> {
  List<StudentRecord> _students = [];
  bool _loading = false;
  String? _error;

  StudentsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await repo.fetchAll();
      if (mounted) setState(() => _students = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load students: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _yearOrdinals = ['1st', '2nd', '3rd', '4th', '5th', '6th'];

  String _yearOrdinal(int year) {
    if (year >= 1 && year <= _yearOrdinals.length) return _yearOrdinals[year - 1];
    return '$year';
  }

  StudentDirectoryModel _toDirectoryModel(StudentRecord s) {
    return StudentDirectoryModel(
      studentId: s.studentNumber,
      avatarInitials: avatarInitialsFor(s.fullName),
      fullName: s.fullName,
      email: '',
      course: s.course,
      yearLevel: _yearOrdinal(s.yearLevelInt),
      section: s.section,
      rfidCard: s.rfidUid.isEmpty ? null : s.rfidUid,
      attendancePercentage: 0,
      violations: 0,
      status: StudentDirectoryStatus.active,
      avatarColor: const Color(0xFF2563EB),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
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
      );
    }

    if (_loading && _students.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return StudentDirectoryPage(
      students: _students.map(_toDirectoryModel).toList(),
    );
  }
}
