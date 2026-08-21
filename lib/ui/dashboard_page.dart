import 'package:flutter/material.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/students_repository.dart';
import '../env.dart';
import '../models/student_record.dart';
import 'admin/rfid_reader_management_connected_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.onReturnToHub});

  final VoidCallback? onReturnToHub;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<StudentRecord> _studentRecords = [];
  bool _loadingList = false;
  bool _busy = false;

  StudentsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
  }

  void _openReaderManagement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RfidReaderManagementConnectedPage(),
      ),
    );
  }

  List<RfidStudentRow> get _rows => _studentRecords.map(_toRow).toList();

  RfidStudentRow _toRow(StudentRecord student) {
    return RfidStudentRow(
      id: student.id,
      rfidNo: student.rfidNo,
      studentNumber: student.studentNumber,
      firstName: student.firstName,
      middleInitial: student.middleInitial,
      lastName: student.lastName,
      course: student.course,
      yearLevel: student.yearLevel,
      section: student.section,
      guardianName: student.guardianName,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadStudents() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _studentRecords = []);
      return;
    }
    setState(() => _loadingList = true);
    try {
      final list = await repo.fetchAll();
      if (mounted) setState(() => _studentRecords = list);
    } catch (e) {
      if (mounted) {
        _toast('Could not load students: $e');
        setState(() => _studentRecords = []);
      }
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _saveStudent(
    RfidRegistrationForm form,
    RfidStudentRow? editing,
  ) async {
    final repo = _repo;
    if (repo == null) {
      _toast(
        'Supabase is not configured. Add `.env` with SUPABASE_URL and SUPABASE_ANON_KEY '
        '(see `.env.example`) or use --dart-define.',
      );
      return;
    }

    final yearLevelInt = StudentRecord.yearLabelToInt(form.yearLevel);

    setState(() => _busy = true);
    try {
      if (editing != null) {
        await repo.update(
          id: editing.id,
          studentNumber: form.studentNumber,
          rfidUid: form.rfidNo,
          firstName: form.firstName,
          middleInitial: form.middleInitial,
          lastName: form.lastName,
          course: form.course,
          yearLevel: yearLevelInt,
          sectionName: form.section,
        );
        _toast('Student updated.');
      } else {
        await repo.create(
          studentNumber: form.studentNumber,
          rfidUid: form.rfidNo,
          firstName: form.firstName,
          middleInitial: form.middleInitial,
          lastName: form.lastName,
          course: form.course,
          yearLevel: yearLevelInt,
          sectionName: form.section,
        );
        _toast('Student registered.');
      }
      await _loadStudents();
    } on StudentsRepositoryException catch (e) {
      _toast(e.message);
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteStudent(RfidStudentRow student) async {
    final repo = _repo;
    if (repo == null) {
      _toast('Supabase is not configured. Add a `.env` file or use --dart-define.');
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.deleteById(student.id);
      _toast('Student removed.');
      await _loadStudents();
    } catch (e) {
      _toast('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> get _banners {
    final banners = <Widget>[];
    if (!AppEnv.supabaseConfigured) {
      banners.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF59E0B)),
          ),
          child: const Text(
            'Supabase env vars are missing; student data will not load. '
            'Run with --dart-define-from-file=supabase_dart_defines.json.',
            style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
          ),
        ),
      );
    } else {
      banners.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Text(
            'Section must match `sections.name` for the selected program and '
            'numeric year (1–4). New students use anonymous sign-in, then profiles + students.',
            style: TextStyle(fontSize: 13, color: Color(0xFF1E3A8A)),
          ),
        ),
      );
    }
    return banners;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStudents());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RfidDashboardPage(
          students: _rows,
          loading: _loadingList,
          busy: _busy,
          onReturnToHub: widget.onReturnToHub,
          bannerWidgets: _banners,
          requireGuardian: false,
          onRefresh: _loadStudents,
          onNotify: _toast,
          onSave: _saveStudent,
          onDelete: _deleteStudent,
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: FloatingActionButton.extended(
            heroTag: 'rfid-reader-management',
            onPressed: () => _openReaderManagement(context),
            icon: const Icon(Icons.sensors),
            label: const Text('Reader Devices'),
          ),
        ),
      ],
    );
  }
}
