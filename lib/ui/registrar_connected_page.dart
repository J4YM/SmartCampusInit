import 'dart:async';
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart'
    show ReportTechnicalIssueCategory, showAppMessage, SectionScheduleRowModel;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auto_refresh.dart';
import '../auth/app_role.dart';
import '../data/academic_term_repository.dart';
import '../data/attendance_activity_repository.dart';
import '../data/curriculum_import_runner.dart';
import '../data/enrollment_import_repository.dart';
import '../data/enrollment_import_runner.dart';
import '../data/grade_import_repository.dart';
import '../data/grade_import_runner.dart';
import '../data/notifications_repository.dart';
import '../data/parent_credential_repository.dart';
import '../data/registrar_repository.dart';
import '../data/rfid_requests_repository.dart';
import '../data/sanctions_repository.dart';
import '../data/schedule_import_repository.dart';
import '../data/schedule_import_runner.dart';
import '../data/section_schedule_repository.dart';
import '../data/students_repository.dart';
import '../data/technical_issues_repository.dart';
import '../documents/section_schedule_pdf.dart';
import '../env.dart';
import 'professor_links_panel.dart';

/// Wires [RegistrarDashboardPage] into the app's navigation. Overview,
/// Student Records, RFID Management, Class Schedule, and Grades are all real
/// (via [RegistrarRepository] — `students`/`profiles`/`sections`/`subjects`/
/// `class_sections`/`grades`). RFID Notify's submit/view-logs flow is real
/// too (via [RfidRequestsRepository] — `rfid_assignment_requests`). The
/// shared notification bell and Report Technical Issue action reuse the
/// same [NotificationsRepository]/[TechnicalIssuesRepository] every other
/// dashboard already uses.
class RegistrarConnectedPage extends StatefulWidget {
  const RegistrarConnectedPage({
    super.key,
    this.registrarName,
    this.registrarProfileId,
    this.onReturnToHub,
    this.onSignOut,
    this.canLiftRestrictions = false,
  });

  /// True only when an Admin has opened this dashboard from the hub: they may
  /// lift a student's "Not for readmission" restriction (the database enforces
  /// it too).
  final bool canLiftRestrictions;

  final String? registrarName;

  /// The signed-in user's `profiles.id`. The static `registrar.demo`
  /// account (lib/auth/static_demo_accounts.dart) has no real Supabase Auth
  /// identity (its id starts with `u_`), so notifications fall back to
  /// role-only broadcasts for it — see [_notifiableUserId].
  final String? registrarProfileId;

  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<RegistrarConnectedPage> createState() => _RegistrarConnectedPageState();
}

class _RegistrarConnectedPageState extends State<RegistrarConnectedPage>
    with AutoRefreshMixin {
  List<NotificationItemModel>? _notifications;
  List<RegistrarStudentModel>? _students;
  OverviewStatsModel? _overviewStats;
  List<ScheduleEntryModel>? _scheduleEntries;
  List<SubjectOption>? _subjectOptions;
  List<TeacherOption>? _teacherOptions;
  List<SectionOption>? _sectionOptions;
  List<String>? _roomOptions;
  List<GradeRecordModel>? _gradeRecords;
  List<CurriculumEntryModel>? _curriculum;
  List<RfidNotificationLogModel>? _myRfidRequests;
  bool _loading = true;
  String? _error;

  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _studentsChannel;
  Timer? _reloadDebounce;
  Timer? _studentsReloadDebounce;

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  TechnicalIssuesRepository? get _issuesRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return TechnicalIssuesRepository(Supabase.instance.client);
  }

  RegistrarRepository? get _registrarRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return RegistrarRepository(Supabase.instance.client);
  }

  ScheduleImportRunner? get _scheduleImportRunner {
    final registrarRepo = _registrarRepo;
    if (!AppEnv.supabaseConfigured || registrarRepo == null) return null;
    return ScheduleImportRunner(
      scheduleImportRepository:
          ScheduleImportRepository(Supabase.instance.client),
      registrarRepository: registrarRepo,
    );
  }

  StudentsRepository? get _studentsRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
  }

  SectionScheduleRepository? get _sectionScheduleRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return SectionScheduleRepository(Supabase.instance.client);
  }

  Future<List<SectionScheduleRowModel>> _handleSectionScheduleSelected(
    String sectionId,
  ) async {
    final repo = _sectionScheduleRepo;
    if (repo == null) return const [];
    final entries = await repo.fetchSectionSchedule(sectionId: sectionId);
    return entries
        .map((e) => SectionScheduleRowModel(
              classSectionId: e.classSectionId,
              subjectCode: e.subjectCode,
              subjectTitle: e.subjectTitle,
              professorName: e.professorName,
              component: e.component,
              day: e.day,
              startTime: e.startTime,
              endTime: e.endTime,
              room: e.room,
              units: e.units,
              schoolYear: e.schoolYear,
              term: e.term,
            ))
        .toList();
  }

  List<SectionSchedulePdfRow> _toPdfRows(List<SectionScheduleRowModel> rows) =>
      rows
          .map((r) => SectionSchedulePdfRow(
                classSectionId: r.classSectionId,
                subjectCode: r.subjectCode,
                subjectTitle: r.subjectTitle,
                professorName: r.professorName,
                component: r.component,
                day: r.day,
                startTime: r.startTime,
                endTime: r.endTime,
                room: r.room,
                units: r.units,
                schoolYear: r.schoolYear,
                term: r.term,
              ))
          .toList();

  Future<void> _handleExportSectionSchedulePdf(
    String sectionName,
    List<SectionScheduleRowModel> rows,
  ) async {
    await exportSectionSchedulePdf(
      sectionName: sectionName,
      rows: _toPdfRows(rows),
    );
  }

  Future<void> _handleExportSectionScheduleExcel(
    String sectionName,
    List<SectionScheduleRowModel> rows,
  ) async {
    await exportSectionScheduleCsv(
      sectionName: sectionName,
      rows: _toPdfRows(rows),
    );
  }

  RfidRequestsRepository? get _rfidRequestsRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return RfidRequestsRepository(Supabase.instance.client);
  }

  /// Matches the fixed profile seeded by
  /// supabase/add_rfid_assignment_requests_schema.sql — keep the two in
  /// sync if it ever changes. Static demo account ids all use the `u_`
  /// prefix (see SessionController.canVerifyPassword), which is how this
  /// tells "demo account, no real profile row" apart from a real Supabase
  /// Auth UUID. Used only for the RFID notify flow's `requested_by` FK —
  /// [_notifiableUserId] stays null for the demo account on purpose, for
  /// the shared notification bell's role-only-broadcast behavior.
  static const _demoRegistrarProfileId = '00000000-0000-4000-8000-000000000003';

  String get _effectiveRegistrarId {
    final id = widget.registrarProfileId;
    if (id == null || id.startsWith('u_')) return _demoRegistrarProfileId;
    return id;
  }

  /// Onboards a new student — the same `students`/`profiles` tables IT
  /// Technician's own Student Records tab already reads and writes, so a
  /// student Registrar adds here shows up there immediately (and vice
  /// versa) with no extra plumbing.
  Future<void> _addStudent(NewStudentForm form) async {
    final repo = _studentsRepo;
    if (repo == null) {
      throw Exception('Supabase is not configured.');
    }
    final yearLevel = _yearLevelLabelToInt(form.yearLevel);
    // No section is typed: the least-full one for this course and year is
    // used (a new one is opened when all are full), as in the batch upload.
    // The registrar can change it afterwards with Change Section.
    final section = await EnrollmentImportRepository(Supabase.instance.client)
        .assignSection(course: form.course, yearLevel: yearLevel);
    final created = await repo.create(
      studentNumber: form.studentNumber,
      rfidUid: '',
      firstName: form.firstName,
      middleInitial: form.middleInitial,
      lastName: form.lastName,
      course: form.course,
      yearLevel: yearLevel,
      sectionId: section.id,
      guardianName: form.guardianName,
      guardianContactNo: form.guardianContactNo,
      email: form.email,
      phoneNumber: form.contactNo,
    );
    await _loadStudents();
    if (form.guardianEmail.isNotEmpty) {
      await _createGuardianLogin(
        studentId: created.id,
        label:
            '${form.studentNumber} ${form.firstName} ${form.lastName}'.trim(),
        guardianEmail: form.guardianEmail,
        guardianName: form.guardianName.isEmpty ? null : form.guardianName,
      );
    }
  }

  /// The "Guardian Email" on Add New Student: creates/links the Parent Portal
  /// login and shows the temporary password once (same panel as the batch
  /// upload and "Parent Portal Login"). A failure here never undoes the
  /// student — they are already saved — it just says what to do next.
  Future<void> _createGuardianLogin({
    required String studentId,
    required String label,
    required String guardianEmail,
    String? guardianName,
  }) async {
    try {
      final issued = await EnrollmentImportRepository(Supabase.instance.client)
          .addGuardianLogin(
        studentId: studentId,
        studentLabel: label,
        guardianEmail: guardianEmail,
        guardianName: guardianName,
      );
      if (!mounted) return;
      if (issued.isEmpty) {
        _toast('$label was added. That guardian email already has a Parent '
            'Portal login (or belongs to another account type) — use Parent '
            'Portal Login on the student\'s profile to issue a new password.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => ParentLoginDialog(
          studentName: label,
          onIssue: () => _handleIssueParentLogin(studentId),
          initialCredentials: [
            for (final c in issued)
              ImportGuardianCredential(
                guardianName: c.guardianName,
                email: c.email,
                temporaryPassword: c.temporaryPassword,
                students: List.of(c.students),
              ),
          ],
        ),
      );
    } catch (e) {
      _toast('$label was added, but the guardian login could not be created: $e');
    }
  }

  int _yearLevelLabelToInt(String label) =>
      ['1st Year', '2nd Year', '3rd Year', '4th Year'].indexOf(label) + 1;

  /// Runs a batch enrollment upload — each student's section is chosen
  /// automatically from their own row's Program/Level. See
  /// EnrollmentImportRunner's own doc comment for the full placement rule.
  Future<ImportStudentsResult> _handleImportStudents({
    required PlatformFile file,
  }) async {
    if (!AppEnv.supabaseConfigured) {
      throw Exception('Supabase is not configured.');
    }
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Could not read "${file.name}" — no data was returned.');
    }
    final runner = EnrollmentImportRepository(Supabase.instance.client);
    final summary = await EnrollmentImportRunner(runner).run(xlsxBytes: bytes);
    await _loadStudents();
    // Sections the import opened must show in the section pickers/filters.
    if (summary.sectionsCreated.isNotEmpty) await _loadSections();
    return ImportStudentsResult(
      created: summary.created,
      updated: summary.updated,
      errors: summary.errors,
      capWarnings: summary.capWarnings,
      restrictedSkipped: summary.restrictedSkipped,
      sectionsCreated: summary.sectionsCreated,
      guardianCredentials: [
        for (final c in summary.guardianCredentials)
          ImportGuardianCredential(
            guardianName: c.guardianName,
            email: c.email,
            temporaryPassword: c.temporaryPassword,
            students: List.of(c.students),
          ),
      ],
    );
  }

  /// Runs a GPA-records batch upload from the Grades tab — see
  /// GradeImportRunner's own doc comment. A separate concept from the
  /// per-subject `grades` this tab otherwise edits, so this doesn't touch
  /// `_gradeRecords`/`_loadGradeRecords` at all.
  Future<ImportGpaRecordsResult> _handleImportGpaRecords({
    required PlatformFile file,
  }) async {
    if (!AppEnv.supabaseConfigured) {
      throw Exception('Supabase is not configured.');
    }
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Could not read "${file.name}" — no data was returned.');
    }
    final runner = GradeImportRepository(Supabase.instance.client);
    final summary = await GradeImportRunner(runner).run(xlsxBytes: bytes);
    // The GWA column of Student Records reads what was just written.
    await Future.wait(
        [_loadStudents(silent: true), _loadGradeRecords(silent: true)]);
    return ImportGpaRecordsResult(
      schoolYear: summary.schoolYear,
      term: summary.term,
      imported: summary.imported,
      skipped: summary.skipped,
      errors: summary.errors,
      skippedStudents: summary.skippedStudents,
    );
  }

  /// Grades tab -> Enter GWA. Re-fetches students so the GWA column of
  /// Student Records shows the new value; returns the term it was filed under.
  Future<String> _handleSaveGwa(String studentId, double gwa) async {
    final repo = _registrarRepo;
    if (repo == null) throw Exception('Supabase is not configured.');
    final term = await repo.saveGwa(studentId: studentId, gwa: gwa);
    await Future.wait(
        [_loadStudents(silent: true), _loadGradeRecords(silent: true)]);
    return term;
  }

  /// Replaces the temporary password of every guardian linked to
  /// [studentId] and returns the new logins for one-time display/export —
  /// the recovery path when the ones from enrollment weren't noted down
  /// (only a hash is stored, so an old one can't be looked up).
  Future<List<ImportGuardianCredential>> _handleIssueParentLogin(
    String studentId,
  ) async {
    if (!AppEnv.supabaseConfigured) {
      throw Exception('Supabase is not configured.');
    }
    final client = Supabase.instance.client;
    final links = await client
        .from('parent_student_links')
        .select('parent_id, profiles!parent_student_links_parent_id_fkey '
            '( first_name, last_name, email )')
        .eq('student_id', studentId) as List;
    if (links.isEmpty) {
      throw Exception(
        'No guardian is linked to this student. Add a Parent/Guardian '
        'email through a batch enrollment upload first.',
      );
    }

    RegistrarStudentModel? student;
    for (final s in _students ?? const <RegistrarStudentModel>[]) {
      if (s.id == studentId) student = s;
    }
    final label = student == null
        ? 'this student'
        : '${student.studentId} ${student.name}'.trim();

    final repo = ParentCredentialRepository(client);
    final issued = <ImportGuardianCredential>[];
    for (final link in links) {
      final profile = link['profiles'] as Map<String, dynamic>?;
      final email = (profile?['email'] as String?)?.trim() ?? '';
      if (email.isEmpty) continue; // nothing to sign in with
      final password =
          await repo.issue(link['parent_id'] as String, reset: true);
      if (password == null) continue;
      final name = [
        (profile?['first_name'] as String? ?? '').trim(),
        (profile?['last_name'] as String? ?? '').trim(),
      ].where((p) => p.isNotEmpty).join(' ');
      issued.add(ImportGuardianCredential(
        guardianName: name.isEmpty ? null : name,
        email: email,
        temporaryPassword: password,
        students: [label],
      ));
    }
    if (issued.isEmpty) {
      throw Exception(
        'The linked guardian has no email on file, so no login can be issued.',
      );
    }
    return issued;
  }

  Future<void> _handleLiftRestriction(String studentId, String reason) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      await repo.liftEnrollmentStanding(studentId, reason: reason);
      await _loadStudents();
      _toast('Restriction lifted. The student can be enrolled again.');
    } catch (e) {
      _toast('Could not lift the restriction: $e');
    }
  }

  /// The Activity Log: gate taps and class attendance, filtered.
  Future<List<ActivityLogEntry>> _handleLoadActivity({
    String? studentQuery,
    String? sectionId,
    String? course,
    DateTime? from,
    DateTime? to,
  }) async {
    final entries = await AttendanceActivityRepository(Supabase.instance.client)
        .fetch(
      studentQuery: studentQuery,
      sectionId: sectionId,
      course: course,
      from: from,
      to: to,
    );
    return [
      for (final e in entries)
        ActivityLogEntry(
          id: e.id,
          at: e.at,
          kind: switch (e.kind) {
            ActivityKind.tapIn => 'tap_in',
            ActivityKind.tapOut => 'tap_out',
            ActivityKind.didNotTapOut => 'did_not_tap_out',
            ActivityKind.classPresent => 'class_present',
            ActivityKind.classLate => 'class_late',
            ActivityKind.classAbsent => 'class_absent',
            ActivityKind.classExcused => 'class_excused',
          },
          label: e.label,
          studentName: e.studentName,
          studentNumber: e.studentNumber,
          section: e.section,
          detail: e.detail,
        ),
    ];
  }

  Future<List<StudentSanctionEntry>> _handleFetchSanctions(
      String studentId) async {
    final sanctions =
        await SanctionsRepository(Supabase.instance.client).forStudent(studentId);
    return [
      for (final s in sanctions)
        StudentSanctionEntry(
          typeLabel: s.sanctionType.label,
          description: s.description,
          effectiveOn: s.effectiveOn,
          affectsEnrollment: s.affectsEnrollment,
        ),
    ];
  }

  Future<void> _handleConfirmEnrollment(String studentId) async {
    await AcademicTermRepository(Supabase.instance.client)
        .confirmEnrollment([studentId]);
    await _loadStudents();
  }

  /// Saves the Student Records tab's "Edit Details" form — see
  /// EditStudentDialog. Throws on failure so the dialog stays open and shows
  /// the message instead of closing as if it had saved.
  Future<void> _handleEditStudent(
      String studentId, EditStudentForm form) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    await repo.updateDetails(
      id: studentId,
      studentNumber: form.studentNumber,
      firstName: form.firstName,
      middleInitial: form.middleInitial,
      lastName: form.lastName,
      email: form.email,
      phoneNumber: form.contactNo,
      guardianName: form.guardianName,
      guardianContactNo: form.guardianContactNo,
    );
    final newEmail = form.guardianEmail.trim();
    RegistrarStudentModel? student;
    for (final s in _students ?? const <RegistrarStudentModel>[]) {
      if (s.id == studentId) student = s;
    }
    final oldEmail = student?.guardianEmail ?? '';
    var createLogin = false;
    if (newEmail.isNotEmpty && newEmail.toLowerCase() != oldEmail.toLowerCase()) {
      // Edits the linked guardian account; false means none is linked yet.
      final updated = await _registrarRepo?.updateGuardianEmail(
              studentId: studentId, email: newEmail) ??
          true;
      createLogin = !updated;
    }
    await _loadStudents();
    if (createLogin) {
      await _createGuardianLogin(
        studentId: studentId,
        label: '${form.studentNumber} ${form.firstName} ${form.lastName}'.trim(),
        guardianEmail: newEmail,
        guardianName: form.guardianName.isEmpty ? null : form.guardianName,
      );
    }
  }

  /// Persists a section override from the Student Records tab's profile
  /// panel — see ChangeSectionDialog's own doc comment.
  Future<void> _handleChangeSection(
    String studentId,
    SectionOption section,
  ) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    await repo.updateSection(
      studentId: studentId,
      sectionId: section.id,
      course: section.program ?? '',
      yearLevel: section.yearLevel,
    );
    await _loadStudents();
  }

  Future<List<StudentEnrollmentModel>> _handleFetchEnrollments(
    String studentId,
  ) async {
    final repo = _registrarRepo;
    if (repo == null) return const [];
    RegistrarStudentModel? student;
    for (final s in _students ?? const <RegistrarStudentModel>[]) {
      if (s.id == studentId) {
        student = s;
        break;
      }
    }
    return repo.fetchStudentEnrollments(
      studentId: studentId,
      homeSectionName: student?.section ?? '',
    );
  }

  Future<List<ClassSectionOffering>> _handleFetchOfferings(
    String subjectId,
  ) async {
    final repo = _registrarRepo;
    if (repo == null) return const [];
    return repo.fetchClassSectionOfferings(subjectId);
  }

  Future<void> _handleEnroll(String studentId, String classSectionId) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    await repo.enrollStudent(
        studentId: studentId, classSectionId: classSectionId);
  }

  Future<void> _handleDrop(String enrollmentId) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    await repo.dropEnrollment(enrollmentId);
  }

  Future<void> _handleDropStudent(String studentId) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    await repo.dropStudent(studentId);
  }

  /// [silent] is a background refresh: no spinner, no error screen over data
  /// that is already showing, nothing to retry — the next tick tries again.
  Future<void> _loadStudents({bool silent = false}) async {
    final repo = _registrarRepo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final students = await repo.fetchStudents();
      // The same numbers RegistrarRepository.fetchOverviewStats derives, from
      // the list just fetched rather than a second full read of `students`.
      final overviewStats = OverviewStatsModel(
        totalStudents: students.length,
        newlyEnrolled: students.where((s) => s.isNewStudent).length,
        rfidPending: students.where((s) => !s.hasRfid).length,
      );
      if (!mounted) return;
      setState(() {
        _students = students;
        _overviewStats = overviewStats;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        debugPrint('Could not refresh students: $e');
      } else {
        setState(() => _error = 'Could not load students: $e');
      }
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadClassScheduleOptions() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final subjects = await repo.fetchSubjects();
      final teachers = await repo.fetchTeachers();
      if (!mounted) return;
      setState(() {
        _subjectOptions = subjects;
        _teacherOptions = teachers;
      });
    } catch (e) {
      _toast('Could not load subjects/teachers: $e');
    }
  }

  /// Room dropdown of the Add Class Schedule form. Best-effort: if the
  /// `rooms` table can't be read the form just keeps a free-text Room field.
  Future<void> _loadRoomOptions() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final rooms = await repo.fetchRoomNumbers();
      if (!mounted) return;
      setState(() => _roomOptions = rooms);
    } catch (e) {
      debugPrint('Could not load rooms: $e');
    }
  }

  Future<void> _loadSections() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final sections = await repo.fetchSections();
      if (!mounted) return;
      setState(() => _sectionOptions = sections);
    } catch (e) {
      _toast('Could not load sections: $e');
    }
  }

  Future<void> _loadScheduleEntries({bool silent = false}) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final entries = await repo.fetchClassSections();
      if (!mounted) return;
      setState(() => _scheduleEntries = entries);
    } catch (e) {
      if (!silent) _toast('Could not load class schedule: $e');
    }
  }

  /// Persists a new `class_sections` offering from the Class Schedule tab's
  /// "Add Class Schedule" dialog, then refreshes the table so the new row
  /// shows up immediately. The section/school year/term are the form's own
  /// real values now — see class_schedule_view.dart's Section dropdown and
  /// School Year/Term fields.
  Future<void> _saveClassSchedule({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      await repo.createClassSection(
        subjectId: subjectId,
        sectionId: sectionId,
        professorId: professorId,
        room: room,
        days: days,
        startTime: startTime,
        endTime: endTime,
        schoolYear: schoolYear,
        term: term,
      );
      await _loadScheduleEntries();
      _toast('Class section created.');
    } catch (e) {
      _toast('Could not create class section: $e');
    }
  }

  /// Saves an edited offering from the Class Schedule table's pencil button,
  /// then refreshes the table.
  Future<void> _updateClassSchedule({
    required String id,
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      await repo.updateClassSection(
        id: id,
        subjectId: subjectId,
        sectionId: sectionId,
        professorId: professorId,
        schoolYear: schoolYear,
        term: term,
        room: room,
        days: days,
        startTime: startTime,
        endTime: endTime,
      );
      await _loadScheduleEntries();
      _toast('Class schedule updated.');
    } catch (e) {
      _toast('Could not update class schedule: $e');
    }
  }

  /// Deletes an offering (after the table's own confirmation), then
  /// refreshes the table.
  Future<void> _deleteClassSchedule(String id) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final dropped = await repo.deleteClassSection(id);
      await _loadScheduleEntries();
      _toast(dropped > 0
          ? 'Class schedule deleted ($dropped enrollment(s) removed).'
          : 'Class schedule deleted.');
    } catch (e) {
      _toast('Could not delete class schedule: $e');
    }
  }

  /// Runs an uploaded Excel schedule export through the import pipeline —
  /// see ScheduleImportRunner. Never rethrows: ClassScheduleView's own
  /// `_handleImportFile` awaits this only to know when to clear its busy
  /// spinner, matching `_saveClassSchedule`'s own catch-and-toast shape.
  Future<void> _handleImportSchedule({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  }) async {
    final runner = _scheduleImportRunner;
    if (runner == null) return;
    try {
      final summary = await runner.run(
        xlsxBytes: bytes,
        schoolYear: schoolYear,
        term: term,
      );
      await _loadScheduleEntries();
      final parts = [
        '${summary.offeringsCommitted} offering(s) imported',
        if (summary.meetingsCommitted > 0)
          '${summary.meetingsCommitted} meeting(s) scheduled',
        if (summary.errors.isNotEmpty) '${summary.errors.length} skipped',
      ];
      _toast(parts.join(', '));
      if (summary.errors.isNotEmpty && mounted) {
        showAppMessage(
          context,
          title: 'Some rows could not be imported',
          message: summary.errors.join('\n\n'),
        );
      }
    } catch (e) {
      _toast('Could not import schedule file: $e');
    }
  }

  Future<void> _loadGradeRecords({bool silent = false}) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final records = await repo.fetchGradeRecords();
      if (!mounted) return;
      setState(() => _gradeRecords = records);
    } catch (e) {
      if (!silent) _toast('Could not load grades: $e');
    }
  }

  /// Saves every currently-visible grade record (Task 2's saveGrade is an
  /// upsert, so re-saving unchanged rows alongside edited ones is
  /// harmless), then reloads so the table reflects server-confirmed state
  /// (including the freshly-recomputed GradeRemark for anything that just
  /// crossed a threshold).
  Future<void> _loadCurriculum() async {
    if (!AppEnv.supabaseConfigured) return;
    try {
      final entries = await CurriculumImportRunner(Supabase.instance.client)
          .fetchCurriculum();
      if (!mounted) return;
      setState(() {
        _curriculum = [
          for (final e in entries)
            CurriculumEntryModel(
              id: e.id,
              subjectId: e.subjectId,
              program: e.program,
              yearLevel: e.yearLevel,
              term: e.term,
              code: e.code,
              title: e.title,
              units: e.units,
              prerequisites: e.prerequisites,
            ),
        ];
      });
    } catch (_) {
      // curriculum_entries may not be migrated yet; the tab shows its empty
      // state and the rest of the dashboard is unaffected.
    }
  }

  /// Curriculum tab Add / Edit Course. Errors (e.g. a code another subject
  /// already uses) propagate so the dialog can show them and stay open.
  Future<void> _handleSaveCurriculumCourse(
    CurriculumEntryModel? existing,
    CurriculumCourseForm form,
  ) async {
    await CurriculumImportRunner(Supabase.instance.client).saveCourse(
      entryId: existing?.id,
      subjectId: existing?.subjectId,
      program: form.program,
      yearLevel: form.yearLevel,
      term: form.term,
      code: form.code,
      title: form.title,
      units: form.units,
      prerequisites: form.prerequisites,
    );
    await _loadCurriculum();
    _toast(existing == null ? 'Course added.' : 'Course updated.');
  }

  Future<void> _handleDeleteCurriculumCourse(CurriculumEntryModel entry) async {
    final id = entry.id;
    if (id == null) return;
    await CurriculumImportRunner(Supabase.instance.client).deleteEntry(id);
    await _loadCurriculum();
    _toast('Course removed from ${entry.program}.');
  }

  /// Curriculum tab upload — see CurriculumImportRunner. Throws on a fatal
  /// problem so the tab shows the message.
  Future<CurriculumUploadResult> _handleUploadCurriculum(
      PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Could not read "${file.name}" — no data was returned.');
    }
    final summary = await CurriculumImportRunner(Supabase.instance.client)
        .run(bytes: bytes, fileName: file.name);
    await _loadCurriculum();
    return CurriculumUploadResult(
      subjects: summary.subjects,
      placements: summary.placements,
      programs: summary.programs,
      mergedAutoSubjects: summary.mergedAutoSubjects,
      errors: summary.errors,
    );
  }

  /// Bulk-enrolls a `class_sections` offering's home section into it (see
  /// RegistrarRepository.enrollSectionStudents), from the Class Schedule
  /// tab's "Enroll this section's students" row action.
  Future<void> _enrollSection(String classSectionId) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final count = await repo.enrollSectionStudents(classSectionId);
      _toast('$count student(s) enrolled.');
    } catch (e) {
      _toast('Enrollment failed: $e');
    }
  }

  Future<void> _loadMyRfidRequests({bool silent = false}) async {
    final repo = _rfidRequestsRepo;
    if (repo == null) return;
    try {
      final requests = await repo.fetchMyRequests(_effectiveRegistrarId);
      if (!mounted) return;
      setState(() {
        _myRfidRequests = requests
            .map((r) => RfidNotificationLogModel(
                  studentName: r.studentName,
                  studentId: r.studentNumber,
                  section: r.section,
                ))
            .toList();
      });
    } catch (e) {
      if (!silent) _toast('Could not load RFID request history: $e');
    }
  }

  Future<void> _submitRfidNotifications(List<String> studentIds) async {
    final repo = _rfidRequestsRepo;
    if (repo == null) return;
    try {
      final count = await repo.notifyRfidMissing(
        studentIds: studentIds,
        registrarId: _effectiveRegistrarId,
      );
      await _loadMyRfidRequests();
      _toast(
        count > 0
            ? 'RFID assignment notice sent for $count student(s).'
            : 'Selected student(s) already have a pending request.',
      );
    } catch (e) {
      _toast('Could not send RFID notice: $e');
    }
  }

  /// Live-refreshes Overview/Student Records/RFID Management when the
  /// underlying `students` table changes elsewhere (e.g. a new
  /// registration, an RFID card getting linked).
  void _subscribeToStudentChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _studentsChannel = Supabase.instance.client
        .channel('public:students:registrar')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'students',
          callback: (_) => _scheduleStudentsReload(),
        )
        .subscribe();
  }

  void _scheduleStudentsReload() {
    _studentsReloadDebounce?.cancel();
    _studentsReloadDebounce =
        Timer(const Duration(milliseconds: 500), _loadStudents);
  }

  String? get _notifiableUserId {
    final id = widget.registrarProfileId;
    if (id == null || id.startsWith('u_')) return null;
    return id;
  }

  Future<void> _loadNotifications() async {
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.registrar,
      userId: _notifiableUserId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  Future<void> _markNotificationsRead() async {
    final repo = _notifRepo;
    if (repo == null) return;
    await repo.markAllReadForRole(AppRole.registrar, userId: _notifiableUserId);
  }

  Future<void> _reportTechnicalIssue({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    await repo.report(
      category: _mapCategory(category),
      description: description,
      location: location,
      reporterId: widget.registrarProfileId ?? 'unknown',
      reporterRole: 'Registrar',
    );
  }

  TechnicalIssueCategory _mapCategory(ReportTechnicalIssueCategory category) {
    switch (category) {
      case ReportTechnicalIssueCategory.offlineDevice:
        return TechnicalIssueCategory.offlineDevice;
      case ReportTechnicalIssueCategory.offlineKiosk:
        return TechnicalIssueCategory.offlineKiosk;
      case ReportTechnicalIssueCategory.classroomPc:
        return TechnicalIssueCategory.classroomPc;
      case ReportTechnicalIssueCategory.other:
        return TechnicalIssueCategory.other;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotifications());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStudents());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadClassScheduleOptions());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSections());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoomOptions());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadScheduleEntries());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGradeRecords());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurriculum());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyRfidRequests());
    _subscribeToNotificationChanges();
    _subscribeToStudentChanges();
    // Realtime covers `students` and `notifications` when those tables are
    // published; everything else (schedule, grades, RFID requests) — and any
    // table whose publication is missing — is picked up by this poll, so no
    // tab needs a manual refresh. Heavier than the other dashboards' (it
    // re-reads every student), hence the longer period.
    startAutoRefresh(_refreshAll, interval: const Duration(seconds: 30));
  }

  /// One quiet pass over every table this dashboard shows.
  Future<void> _refreshAll() => Future.wait([
        _loadStudents(silent: true),
        _loadNotifications(),
        _loadScheduleEntries(silent: true),
        _loadGradeRecords(silent: true),
        _loadMyRfidRequests(silent: true),
        _loadCurriculum(),
      ]);

  /// Live-refreshes the bell when a new notification lands for this
  /// dashboard. Requires `notifications` to be in the `supabase_realtime`
  /// publication (see supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:registrar')
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

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _studentsReloadDebounce?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    final studentsChannel = _studentsChannel;
    if (studentsChannel != null) {
      Supabase.instance.client.removeChannel(studentsChannel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _students == null && !_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadStudents,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  textStyle: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RegistrarDashboardPage(
      isLoading: _loading && _students == null,
      registrarName: widget.registrarName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialStudents: _students,
      initialOverviewStats: _overviewStats,
      initialScheduleEntries: _scheduleEntries,
      initialSubjectOptions: _subjectOptions,
      initialTeacherOptions: _teacherOptions,
      initialSectionOptions: _sectionOptions,
      initialRoomOptions: _roomOptions,
      initialGradeRecords: _gradeRecords,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onMarkNotificationRead:
          _notifRepo == null ? null : (id) => _notifRepo!.markRead(id),
      onReportTechnicalIssue:
          _issuesRepo == null ? null : _reportTechnicalIssue,
      onAddStudent: _studentsRepo == null ? null : _addStudent,
      onImportStudents: _studentsRepo == null ? null : _handleImportStudents,
      curriculumEntries: _curriculum,
      professorsTabBuilder: AppEnv.supabaseConfigured
          ? (_) => ProfessorLinksPanel(
                actorName: widget.registrarName ?? 'Registrar',
                actorRole: AppRole.registrar,
                actorId: (widget.registrarProfileId?.startsWith('u_') ?? true)
                    ? null
                    : widget.registrarProfileId,
              )
          : null,
      onUploadCurriculum:
          AppEnv.supabaseConfigured ? _handleUploadCurriculum : null,
      onSaveCurriculumCourse:
          AppEnv.supabaseConfigured ? _handleSaveCurriculumCourse : null,
      onDeleteCurriculumCourse:
          AppEnv.supabaseConfigured ? _handleDeleteCurriculumCourse : null,
      onImportGpaRecords:
          AppEnv.supabaseConfigured ? _handleImportGpaRecords : null,
      onSaveGwa: _registrarRepo == null ? null : _handleSaveGwa,
      onChangeSection: _studentsRepo == null ? null : _handleChangeSection,
      onConfirmEnrollment:
          _studentsRepo == null ? null : _handleConfirmEnrollment,
      onFetchSanctions:
          AppEnv.supabaseConfigured ? _handleFetchSanctions : null,
      onLoadActivity: AppEnv.supabaseConfigured ? _handleLoadActivity : null,
      onLiftRestriction: widget.canLiftRestrictions && _registrarRepo != null
          ? _handleLiftRestriction
          : null,
      onEditStudent: _studentsRepo == null ? null : _handleEditStudent,
      onIssueParentLogin: !AppEnv.supabaseConfigured
          ? null
          : _handleIssueParentLogin,
      onFetchEnrollments:
          _registrarRepo == null ? null : _handleFetchEnrollments,
      onFetchOfferings: _registrarRepo == null ? null : _handleFetchOfferings,
      onEnroll: _registrarRepo == null ? null : _handleEnroll,
      onDrop: _registrarRepo == null ? null : _handleDrop,
      onDropStudent: _registrarRepo == null ? null : _handleDropStudent,
      onSaveClassSchedule: _registrarRepo == null ? null : _saveClassSchedule,
      onUpdateClassSchedule:
          _registrarRepo == null ? null : _updateClassSchedule,
      onDeleteClassSchedule:
          _registrarRepo == null ? null : _deleteClassSchedule,
      onImportSchedule:
          _scheduleImportRunner == null ? null : _handleImportSchedule,
      onEnrollSection: _registrarRepo == null ? null : _enrollSection,
      sectionScheduleOptions: (_sectionOptions ?? const [])
          .map((s) => (id: s.id, name: s.name))
          .toList(),
      onSectionScheduleSelected:
          _sectionScheduleRepo == null ? null : _handleSectionScheduleSelected,
      onExportSectionSchedulePdf: _handleExportSectionSchedulePdf,
      onExportSectionScheduleExcel: _handleExportSectionScheduleExcel,
      initialRfidNotificationLogs: _myRfidRequests,
      onSubmitNotify:
          _rfidRequestsRepo == null ? null : _submitRfidNotifications,
    );
  }
}
