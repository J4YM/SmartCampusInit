import 'dart:async';
import 'dart:typed_data';

import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/notifications_repository.dart';
import '../data/rfid_reader_repository.dart';
import '../data/students_repository.dart';
import '../data/technical_issues_repository.dart';
import '../documents/student_id_card_pdf.dart';
import '../env.dart';
import '../models/student_record.dart';

/// Wires [ItTechnicianDashboardPage] and its three tabs to Supabase — the
/// student directory (paginated), the reader-device network, and the
/// technical-issue ticket queue, plus the shared notification bell.
class ItTechnicianConnectedPage extends StatefulWidget {
  const ItTechnicianConnectedPage({
    super.key,
    this.technicianName,
    this.technicianProfileId,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? technicianName;
  final String? technicianProfileId;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<ItTechnicianConnectedPage> createState() => _ItTechnicianConnectedPageState();
}

class _ItTechnicianConnectedPageState extends State<ItTechnicianConnectedPage> {
  // Student Records state
  // Matches Admin's/Discipline Officer's own student-table page size
  // convention (server-side `fetchPage(pageSize: ...)`), tuned to 20 per
  // this dashboard's own requirement.
  static const _pageSize = 20;
  List<StudentRecord> _students = [];
  bool _studentsLoading = false;
  bool _studentsBusy = false;
  int _page = 1;
  int _totalPages = 1;
  int? _totalCount;
  String _course = 'All Courses';
  String _yearLevel = 'All Years';
  String _section = 'All Sections';
  List<String> _sectionOptions = [];
  String _searchQuery = '';

  // Reader Devices state
  List<RfidReaderRecord> _readers = [];
  bool _readersBusy = false;

  // Technical Issues state
  List<TechnicalIssueReport> _reports = [];
  bool _reportsLoading = false;
  String _statusFilterLabel = 'All';

  // Overview state — deliberately separate from the Student Records /
  // Technical Issues tab state above, which is filtered by whatever the user
  // currently has selected in those tabs. The Overview cards must show true
  // totals, so they get their own unfiltered fetch. (Reader counts need no
  // equivalent: `_readers` is never filtered.)
  int? _overviewTotalStudentCount;
  int? _overviewOpenTicketCount;

  // Notifications
  List<NotificationItemModel>? _notifications;
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  static const _demoTechnicianProfileId = '00000000-0000-4000-8000-000000000099';

  String get _effectiveTechnicianId {
    final id = widget.technicianProfileId;
    if (id == null || id.startsWith('u_')) return _demoTechnicianProfileId;
    return id;
  }

  StudentsRepository? get _studentsRepo =>
      AppEnv.supabaseConfigured ? StudentsRepository(Supabase.instance.client) : null;
  RfidReaderRepository? get _readerRepo =>
      AppEnv.supabaseConfigured ? RfidReaderRepository(Supabase.instance.client) : null;
  TechnicalIssuesRepository? get _issuesRepo =>
      AppEnv.supabaseConfigured ? TechnicalIssuesRepository(Supabase.instance.client) : null;
  NotificationsRepository? get _notifRepo =>
      AppEnv.supabaseConfigured ? NotificationsRepository(Supabase.instance.client) : null;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Student Records -------------------------------------------------

  Future<void> _loadStudents() async {
    final repo = _studentsRepo;
    if (repo == null) return;
    setState(() => _studentsLoading = true);
    try {
      final course = _course == 'All Courses' ? null : _course;
      final yearLevel = _yearLevel == 'All Years'
          ? null
          : _yearLevelOptionToInt(_yearLevel);
      String? sectionId;
      if (_section != 'All Sections' && course != null && yearLevel != null) {
        sectionId = await repo.findSectionId(program: course, yearLevel: yearLevel, sectionName: _section);
      }
      final result = await repo.fetchPage(
        page: _page,
        pageSize: _pageSize,
        course: course,
        yearLevel: yearLevel,
        sectionId: sectionId,
        studentNumberQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (!mounted) return;
      setState(() {
        _students = result.items;
        _totalCount = result.totalCount;
        _totalPages = (result.totalCount / _pageSize).ceil().clamp(1, 1 << 30);
      });
      if (course != null && yearLevel != null) {
        final sections = await repo.fetchSectionNames(program: course, yearLevel: yearLevel);
        if (mounted) setState(() => _sectionOptions = sections);
      }
    } catch (e) {
      _toast('Could not load students: $e');
    } finally {
      if (mounted) setState(() => _studentsLoading = false);
    }
  }

  /// Section names only exist for a specific (course, year level) pair — see
  /// [_loadStudents]'s `fetchSectionNames` call.
  bool get _sectionFilterApplies =>
      _course != 'All Courses' && _yearLevel != 'All Years';

  int _yearLevelOptionToInt(String label) =>
      ['1st Year', '2nd Year', '3rd Year', '4th Year'].indexOf(label) + 1;

  List<RfidStudentRow> get _studentRows => _students
      .map((s) => RfidStudentRow(
            id: s.id,
            rfidNo: s.rfidNo,
            studentNumber: s.studentNumber,
            firstName: s.firstName,
            middleInitial: s.middleInitial,
            lastName: s.lastName,
            course: s.course,
            yearLevel: s.yearLevel,
            section: s.section,
            guardianName: s.guardianName,
            photoPath: s.photoPath,
          ))
      .toList();

  // --- Student ID printing -----------------------------------------------

  Future<void> _handlePrintId(RfidStudentRow student) async {
    final repo = _studentsRepo;
    if (repo == null) return;

    Uint8List? existingPhoto;
    try {
      final url = await repo.fetchStudentPhotoUrl(student.photoPath);
      if (url != null) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) existingPhoto = response.bodyBytes;
      }
    } catch (e) {
      debugPrint('Could not load existing student photo: $e');
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => IdCardPrintDialog(
        student: student,
        initialPhotoBytes: existingPhoto,
        onPrint: (photoBytes) => _printStudentId(student, photoBytes),
      ),
    );
  }

  Future<void> _printStudentId(
    RfidStudentRow student,
    Uint8List photoBytes,
  ) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    await repo.uploadStudentPhoto(studentId: student.id, bytes: photoBytes);
    await printStudentIdCard(
      StudentIdCardData(
        name: student.fullName,
        studentNumber: student.studentNumber,
        program: student.course,
        section: student.section,
        photoBytes: photoBytes,
      ),
    );
    await _loadStudents();
  }

  Future<void> _saveStudent(RfidRegistrationForm form, RfidStudentRow? editing) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    final yearLevelInt = StudentRecord.yearLabelToInt(form.yearLevel);
    setState(() => _studentsBusy = true);
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
      }
      await _loadStudents();
      await _loadOverviewStats();
      // No catch here: `_StudentFormDialog.onSave`'s own try/catch (Task 8)
      // already displays the error inline and keeps the dialog open on
      // failure — catching and rethrowing here would add nothing.
    } finally {
      if (mounted) setState(() => _studentsBusy = false);
    }
  }

  Future<void> _deleteStudent(RfidStudentRow student) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    setState(() => _studentsBusy = true);
    try {
      await repo.deleteById(student.id);
      await _loadStudents();
      await _loadOverviewStats();
    } catch (e) {
      _toast('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _studentsBusy = false);
    }
  }

  // --- Reader Devices ----------------------------------------------------

  Future<void> _loadReaders() async {
    final repo = _readerRepo;
    if (repo == null) return;
    try {
      final readers = await repo.fetchReaders(includeInactive: true);
      if (mounted) setState(() => _readers = readers);
    } catch (e) {
      _toast('Could not load readers: $e');
    }
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return 'never';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  RfidReaderRowModel _toReaderRow(RfidReaderRecord r) => RfidReaderRowModel(
        id: r.id,
        label: r.label,
        usbSerial: r.usbSerial,
        location: r.location,
        isKioskReader: r.isKioskReader,
        isActive: r.isActive,
        isOnline: r.isOnline,
        lastSeenLabel: _relativeTime(r.lastSeenAt),
      );

  Future<void> _addReader({required String label, required String usbSerial, String? location}) async {
    final repo = _readerRepo;
    if (repo == null) return;
    setState(() => _readersBusy = true);
    try {
      await repo.addReader(label: label, usbSerial: usbSerial, location: location);
      await _loadReaders();
    } finally {
      if (mounted) setState(() => _readersBusy = false);
    }
  }

  Future<void> _updateReader({
    required String id,
    required String label,
    required String usbSerial,
    String? location,
  }) async {
    final repo = _readerRepo;
    if (repo == null) return;
    setState(() => _readersBusy = true);
    try {
      await repo.updateReader(id: id, label: label, usbSerial: usbSerial, location: location);
      await _loadReaders();
    } finally {
      if (mounted) setState(() => _readersBusy = false);
    }
  }

  Future<void> _setReaderActive(String id, bool isActive) async {
    final repo = _readerRepo;
    if (repo == null) return;
    setState(() => _readersBusy = true);
    try {
      await repo.setReaderActive(id, isActive);
      await _loadReaders();
    } catch (e) {
      _toast('Could not update reader: $e');
    } finally {
      if (mounted) setState(() => _readersBusy = false);
    }
  }

  // --- Technical Issues ----------------------------------------------------

  TechnicalIssueStatus? _statusFilterValue() {
    switch (_statusFilterLabel) {
      case 'Open':
        return TechnicalIssueStatus.open;
      case 'In Progress':
        return TechnicalIssueStatus.inProgress;
      case 'Resolved':
        return TechnicalIssueStatus.resolved;
      default:
        return null;
    }
  }

  Future<void> _loadReports() async {
    final repo = _issuesRepo;
    if (repo == null) return;
    setState(() => _reportsLoading = true);
    try {
      final reports = await repo.fetchReports(status: _statusFilterValue());
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      _toast('Could not load technical issues: $e');
    } finally {
      if (mounted) setState(() => _reportsLoading = false);
    }
  }

  TechnicalIssueRowModel _toReportRow(TechnicalIssueReport r) => TechnicalIssueRowModel(
        id: r.id,
        categoryLabel: r.category.label,
        description: r.description,
        location: r.location,
        reportedByLabel: r.reportedByRole,
        status: r.status.dbValue,
        statusLabel: r.status.label,
        createdAtLabel: _relativeTime(r.createdAt),
      );

  Future<List<TechnicalIssueCommentRowModel>> _loadComments(String reportId) async {
    final repo = _issuesRepo;
    if (repo == null) return const [];
    final comments = await repo.fetchComments(reportId);
    return comments
        .map((c) => TechnicalIssueCommentRowModel(
              id: c.id,
              authorLabel: c.authorRole,
              message: c.message,
              createdAtLabel: _relativeTime(c.createdAt),
            ))
        .toList();
  }

  // Neither of the two writes below catches: the ticket detail dialog
  // (technical_issues_tab.dart) needs the failure to reach it so it can keep
  // the user's typed reply / revert its optimistic status selection, and it
  // shows the error itself. Same reasoning as `_saveStudent` above.
  Future<void> _addComment(String reportId, String message) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    await repo.addComment(
      reportId: reportId,
      message: message,
      authorId: _effectiveTechnicianId,
      authorRole: 'IT_Technician',
    );
  }

  Future<void> _changeStatus(String reportId, String newStatusValue) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    final status = technicalIssueStatusFromDb(newStatusValue);
    await repo.updateStatus(id: reportId, status: status, resolvedBy: _effectiveTechnicianId);
    await _loadReports();
    await _loadOverviewStats();
  }

  // --- Overview stats ----------------------------------------------------

  /// True, unfiltered totals for the Overview tab's stat cards. Deliberately
  /// does not reuse `_totalCount`/`_reports`, which both track the *filtered*
  /// state of their own tab.
  Future<void> _loadOverviewStats() async {
    final studentsRepo = _studentsRepo;
    final issuesRepo = _issuesRepo;
    try {
      if (studentsRepo != null) {
        // pageSize: 1 — only `.totalCount` is read, so there's no reason to
        // pull a whole extra page of rows just to count them.
        final result = await studentsRepo.fetchPage(page: 1, pageSize: 1);
        if (!mounted) return;
        setState(() => _overviewTotalStudentCount = result.totalCount);
      }
      if (issuesRepo != null) {
        final allReports = await issuesRepo.fetchReports();
        if (!mounted) return;
        setState(() => _overviewOpenTicketCount = allReports
            .where((r) => r.status != TechnicalIssueStatus.resolved)
            .length);
      }
    } catch (e) {
      // Not toasted: the tabs' own loaders already surface the same backend
      // failure, and a second snackbar for the summary cards would only
      // duplicate it.
      debugPrint('Could not load overview stats: $e');
    }
  }

  // --- Notifications ----------------------------------------------------

  Future<void> _loadNotifications() async {
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.itTechnician,
      userId: _effectiveTechnicianId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  Future<void> _markNotificationsRead() async {
    await _notifRepo?.markAllReadForRole(AppRole.itTechnician, userId: _effectiveTechnicianId);
  }

  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:it_technician')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            _reloadDebounce?.cancel();
            _reloadDebounce = Timer(const Duration(milliseconds: 400), _loadNotifications);
          },
        )
        .subscribe();
  }

  // --- Lifecycle ----------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudents();
      _loadReaders();
      _loadReports();
      _loadOverviewStats();
      _loadNotifications();
    });
    _subscribeToNotificationChanges();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ItTechnicianDashboardPage(
      technicianName: widget.technicianName ?? 'IT Technician',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialStats: ItTechnicianOverviewStats(
        totalStudents: _overviewTotalStudentCount ?? 0,
        totalReaders: _readers.length,
        onlineReaders: _readers.where((r) => r.isOnline).length,
        openTicketCount: _overviewOpenTicketCount ?? 0,
      ),
      initialNotifications: _notifications,
      onMarkNotificationsRead: _notifRepo == null ? null : _markNotificationsRead,
      studentRecordsTabBuilder: (_) => StudentRecordsTab(
        students: _studentRows,
        isLoading: _studentsLoading,
        isBusy: _studentsBusy,
        currentPage: _page,
        totalPages: _totalPages,
        totalCount: _totalCount,
        selectedCourse: _course,
        selectedYearLevel: _yearLevel,
        selectedSection: _section,
        sectionOptions: _sectionOptions,
        onSearchChanged: (value) {
          _searchQuery = value;
          _page = 1;
          _loadStudents();
        },
        onCourseChanged: (value) {
          setState(() {
            _course = value;
            _section = 'All Sections';
            _page = 1;
            // `_loadStudents` can only refill these when course AND year are
            // both specific; without this the dropdown would keep offering
            // the previous pair's sections, which it would then ignore.
            if (!_sectionFilterApplies) _sectionOptions = [];
          });
          _loadStudents();
        },
        onYearLevelChanged: (value) {
          setState(() {
            _yearLevel = value;
            _section = 'All Sections';
            _page = 1;
            if (!_sectionFilterApplies) _sectionOptions = [];
          });
          _loadStudents();
        },
        onSectionChanged: (value) {
          setState(() {
            _section = value;
            _page = 1;
          });
          _loadStudents();
        },
        onPreviousPage: () {
          if (_page <= 1) return;
          setState(() => _page -= 1);
          _loadStudents();
        },
        onNextPage: () {
          if (_page >= _totalPages) return;
          setState(() => _page += 1);
          _loadStudents();
        },
        onSave: _saveStudent,
        onDelete: _deleteStudent,
        onPrintId: _studentsRepo == null ? null : _handlePrintId,
      ),
      readerDevicesTabBuilder: (_) => RfidReaderManagementPage(
        embedded: true,
        readers: _readers.map(_toReaderRow).toList(),
        isBusy: _readersBusy,
        onAddReader: _addReader,
        onUpdateReader: _updateReader,
        onSetActive: _setReaderActive,
      ),
      technicalIssuesTabBuilder: (_) => TechnicalIssuesTab(
        reports: _reports.map(_toReportRow).toList(),
        isLoading: _reportsLoading,
        statusFilter: _statusFilterLabel,
        onStatusFilterChanged: (label) {
          setState(() => _statusFilterLabel = label);
          _loadReports();
        },
        onLoadComments: _loadComments,
        onAddComment: _addComment,
        onChangeStatus: _changeStatus,
      ),
    );
  }
}
