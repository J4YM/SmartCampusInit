import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/session_controller.dart';
import '../../data/students_repository.dart';
import '../../env.dart';
import '../../models/student_record.dart';
import 'staff_role_mapping.dart' show avatarInitialsFor;
import 'student_directory_dialogs.dart';

const _courseAbbreviations = <String, String>{
  'BSIT': 'BS Information Technology',
  'BSTM': 'BS Tourism Management',
  'BSBA': 'BS Business Administration',
  'BSHM': 'BS Hospitality Management',
};

const _yearLabelToInt = <String, int>{
  '1st': 1,
  '2nd': 2,
  '3rd': 3,
  '4th': 4,
};

/// Wires the presentation-only [StudentDirectoryPage] (from `admin_dashboard`)
/// to Supabase via [StudentsRepository] — the same repository already used by
/// the RFID Management module (`lib/ui/dashboard_page.dart`).
///
/// Fetches one page at a time (see `StudentsRepository.fetchPage`) instead
/// of the whole directory, and wires the row actions to real View/Edit/
/// Delete flows (`student_directory_dialogs.dart`) instead of the
/// presentation package's snackbar-only demo behavior.
class StudentDirectoryConnectedPage extends StatefulWidget {
  const StudentDirectoryConnectedPage({super.key, required this.session});

  final SessionController session;

  @override
  State<StudentDirectoryConnectedPage> createState() =>
      _StudentDirectoryConnectedPageState();
}

class _StudentDirectoryConnectedPageState
    extends State<StudentDirectoryConnectedPage> {
  List<StudentRecord> _students = [];
  Map<String, StudentRecord> _byStudentNumber = {};
  int _page = 1;
  int _totalCount = 0;
  bool _loading = false;
  String? _error;
  String? _courseFilter;
  int? _yearFilter;

  /// The page size the directory was last fetched with — compared against
  /// the live [_pageSize] in [didChangeDependencies] so a resize/rotation
  /// that crosses [kPaginationMobileBreakpoint] re-fetches page 1 at the
  /// new density instead of leaving stale rows on screen under a
  /// now-mismatched page indicator.
  int? _fetchedPageSize;

  /// 5 rows on a narrow phone, 10 at tablet width and up (see
  /// [ResponsiveX.cardPageSize]).
  int get _pageSize => context.cardPageSize;

  StudentsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
  }

  int get _totalPages =>
      _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    final pageSize = _pageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await repo.fetchPage(
        page: _page,
        pageSize: pageSize,
        course: _courseFilter,
        yearLevel: _yearFilter,
      );
      if (!mounted) return;
      setState(() {
        _students = result.items;
        _byStudentNumber = {for (final s in result.items) s.studentNumber: s};
        _totalCount = result.totalCount;
        _fetchedPageSize = pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load students: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fires whenever an inherited dependency this widget reads — including
  /// `MediaQuery`, via [_pageSize] — changes, e.g. a window resize or
  /// device rotation. Re-fetches page 1 at the new density whenever that
  /// actually crosses the mobile/desktop [_pageSize] bucket, so the
  /// directory on screen never silently mismatches the page indicator/count.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fetchedPageSize != null && _fetchedPageSize != _pageSize) {
      _page = 1;
      _load();
    }
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _load();
  }

  void _onCourseFilterChanged(String label) {
    final course = label == 'All Courses' ? null : _courseAbbreviations[label];
    if (course == _courseFilter) return;
    setState(() {
      _courseFilter = course;
      _page = 1;
    });
    _load();
  }

  void _onYearFilterChanged(String label) {
    final year = label == 'All Years' ? null : _yearLabelToInt[label];
    if (year == _yearFilter) return;
    setState(() {
      _yearFilter = year;
      _page = 1;
    });
    _load();
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleView(StudentDirectoryModel model) async {
    final student = _byStudentNumber[model.studentId];
    if (student == null) return;
    await showStudentViewDialog(context, student);
  }

  Future<void> _handleEdit(StudentDirectoryModel model) async {
    final repo = _repo;
    final student = _byStudentNumber[model.studentId];
    if (repo == null || student == null) return;

    final result = await showStudentEditDialog(
      context,
      student,
      fetchSectionNames: repo.fetchSectionNames,
    );
    if (result == null) return;

    try {
      await repo.update(
        id: student.id,
        studentNumber: student.studentNumber,
        rfidUid: student.rfidUid,
        firstName: result.firstName,
        middleInitial: result.middleInitial,
        lastName: result.lastName,
        course: result.course,
        yearLevel: result.yearLevel,
        sectionName: result.sectionName,
      );
      _toast('${student.fullName}\'s record was updated.');
      await _load();
    } catch (e) {
      _toast('Could not update this student: $e');
    }
  }

  Future<void> _handleDelete(StudentDirectoryModel model) async {
    final repo = _repo;
    final student = _byStudentNumber[model.studentId];
    if (repo == null || student == null) return;

    final confirmed = await showStudentDeleteDialog(context, student, widget.session);
    if (!confirmed) return;

    try {
      await repo.deleteById(student.id);
      _toast('${student.fullName}\'s record was deleted.');
      await _load();
    } catch (e) {
      _toast('Could not delete this student: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _students.isEmpty) {
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

    return StudentDirectoryPage(
      students: _students.map(_toDirectoryModel).toList(),
      isLoading: _loading,
      currentPage: _page,
      totalPages: _totalPages,
      totalCount: _totalCount,
      onPreviousPage: () => _goToPage(_page - 1),
      onNextPage: () => _goToPage(_page + 1),
      onCourseFilterChanged: _onCourseFilterChanged,
      onYearFilterChanged: _onYearFilterChanged,
      onView: _handleView,
      onEdit: _handleEdit,
      onDelete: _handleDelete,
    );
  }
}
