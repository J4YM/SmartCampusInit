import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase (`good_moral_requests` / `students`) ready.
// fromJson()/toJson() map directly onto snake_case Postgres columns so rows
// can be streamed straight into these models once the backend is wired up.
// ---------------------------------------------------------------------------

class GoodMoralRequestModel {
  const GoodMoralRequestModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    required this.documentType,
    required this.purpose,
    required this.requestedBy,
    required this.requestDateTime,
    this.remarks = '',
    this.hasActiveViolation = false,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String programGradeSection;

  /// e.g. "Good Moral Certificate", "Certificate of Clearance".
  final String documentType;

  /// e.g. "Employment", "Scholarship application", "School transfer".
  final String purpose;
  final String requestedBy;
  final DateTime requestDateTime;
  final String remarks;

  /// True when this student currently has a `student_violations` row with
  /// status `Pending`/`Under_Investigation` (and not archived) — drives the
  /// Preview panel's Clearance Status banner. Computed by
  /// `DisciplineRepository.fetchGoodMoralRequests`.
  final bool hasActiveViolation;

  factory GoodMoralRequestModel.fromJson(Map<String, dynamic> json) {
    return GoodMoralRequestModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentNumber: json['student_number'] as String,
      programGradeSection: json['program_grade_section'] as String,
      documentType: json['document_type'] as String,
      purpose: json['purpose'] as String,
      requestedBy: json['requested_by'] as String,
      requestDateTime: DateTime.parse(json['request_datetime'] as String),
      remarks: json['remarks'] as String? ?? '',
      hasActiveViolation: json['has_active_violation'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_number': studentNumber,
      'program_grade_section': programGradeSection,
      'document_type': documentType,
      'purpose': purpose,
      'requested_by': requestedBy,
      'request_datetime': requestDateTime.toIso8601String(),
      'remarks': remarks,
      'has_active_violation': hasActiveViolation,
    };
  }
}

/// Master directory entry for an enrolled student — independent of any
/// pending Good Moral request. Supabase (`students`) ready.
class StudentDirectoryEntryModel {
  const StudentDirectoryEntryModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    this.program = '',
    this.yearLevel = 0,
    this.status = 'Enrolled',
    this.previousViolationsCount = 0,
    this.hasActiveViolation = false,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String programGradeSection;

  /// `sections.program` (e.g. "BS Information Technology") — separate from
  /// [programGradeSection]'s combined display string so the Student List
  /// can group by it without re-parsing that string.
  final String program;

  /// `sections.year_level` (1-4).
  final int yearLevel;
  final String status;

  /// `student_violations` count for this student (archived rows excluded) —
  /// drives the Preview panel's "Previous violations" field when browsing
  /// the Student List (the Requests tab shows Request Details instead of
  /// this).
  final int previousViolationsCount;

  /// True when this student currently has a `student_violations` row with
  /// status `Pending`/`Under_Investigation` (and not archived) — drives the
  /// Preview panel's Clearance Status banner. Computed by
  /// `DisciplineRepository.fetchStudentDirectoryPage`.
  final bool hasActiveViolation;

  factory StudentDirectoryEntryModel.fromJson(Map<String, dynamic> json) {
    return StudentDirectoryEntryModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentNumber: json['student_number'] as String,
      programGradeSection: json['program_grade_section'] as String,
      program: json['program'] as String? ?? '',
      yearLevel: json['year_level'] as int? ?? 0,
      status: json['status'] as String? ?? 'Enrolled',
      previousViolationsCount: json['previous_violations_count'] as int? ?? 0,
      hasActiveViolation: json['has_active_violation'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_number': studentNumber,
      'program_grade_section': programGradeSection,
      'program': program,
      'year_level': yearLevel,
      'status': status,
      'previous_violations_count': previousViolationsCount,
      'has_active_violation': hasActiveViolation,
    };
  }
}

/// Unifies a queued [GoodMoralRequestModel] and a plain
/// [StudentDirectoryEntryModel] into the one shape the Preview panel needs —
/// either the Requests queue or the Students List directory can populate the
/// selection, and the panel shouldn't care which one it came from.
class GoodMoralSelectedStudent {
  const GoodMoralSelectedStudent({
    required this.sourceId,
    required this.sourceSubTab,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    this.documentType,
    this.purpose,
    this.requestedBy,
    this.requestDateTime,
    this.remarks = '',
    this.previousViolationsCount,
    this.hasActiveViolation = false,
  });

  /// The originating [GoodMoralRequestModel.id] or
  /// [StudentDirectoryEntryModel.id] — lets a list tile tell whether *it* is
  /// the current selection without caring about the other list.
  final String sourceId;
  final GoodMoralSubTab sourceSubTab;

  final String studentName;
  final String studentNumber;
  final String programGradeSection;
  final String? documentType;
  final String? purpose;
  final String? requestedBy;
  final DateTime? requestDateTime;
  final String remarks;

  /// Only populated when [sourceSubTab] is [GoodMoralSubTab.studentsList] —
  /// the Requests tab shows Request Details instead of this field.
  final int? previousViolationsCount;

  /// True when this student currently has an active (`Pending`/
  /// `Under_Investigation`, non-archived) violation — drives the Preview
  /// panel's Clearance Status banner (see [GoodMoralPreviewPanel]).
  final bool hasActiveViolation;

  factory GoodMoralSelectedStudent.fromRequest(GoodMoralRequestModel request) {
    return GoodMoralSelectedStudent(
      sourceId: request.id,
      sourceSubTab: GoodMoralSubTab.requests,
      studentName: request.studentName,
      studentNumber: request.studentNumber,
      programGradeSection: request.programGradeSection,
      documentType: request.documentType,
      purpose: request.purpose,
      requestedBy: request.requestedBy,
      requestDateTime: request.requestDateTime,
      remarks: request.remarks,
      hasActiveViolation: request.hasActiveViolation,
    );
  }

  factory GoodMoralSelectedStudent.fromDirectoryEntry(
    StudentDirectoryEntryModel student,
  ) {
    return GoodMoralSelectedStudent(
      sourceId: student.id,
      sourceSubTab: GoodMoralSubTab.studentsList,
      studentName: student.studentName,
      studentNumber: student.studentNumber,
      programGradeSection: student.programGradeSection,
      previousViolationsCount: student.previousViolationsCount,
      hasActiveViolation: student.hasActiveViolation,
    );
  }
}

// ---------------------------------------------------------------------------
// Good Moral Management — sub-tab navigation + state controller
// ---------------------------------------------------------------------------

/// Which queue is showing in the Good Moral Management left panel.
enum GoodMoralSubTab { requests, studentsList }

/// Owns every piece of state behind the Good Moral Management view: which
/// sub-tab (Requests / Students List) is active, the two source lists, and
/// the single selection shared by both — since either list can populate the
/// Preview panel on the right, selection lives here rather than in either
/// list's own widget.
class GoodMoralDashboardController extends ChangeNotifier {
  GoodMoralSubTab _activeSubTab = GoodMoralSubTab.requests;
  GoodMoralSubTab get activeSubTab => _activeSubTab;

  List<GoodMoralRequestModel> _requests = const [];
  List<GoodMoralRequestModel> get requests => _requests;

  List<StudentDirectoryEntryModel> _students = const [];
  List<StudentDirectoryEntryModel> get students => _students;

  GoodMoralSelectedStudent? _selectedStudentRequest;
  GoodMoralSelectedStudent? get selectedStudentRequest =>
      _selectedStudentRequest;

  /// True when nothing is selected — drives the Preview panel's empty state
  /// and disables the "Generate & Print Certificate" action.
  bool get isEmptyState => _selectedStudentRequest == null;

  void selectSubTab(GoodMoralSubTab tab) {
    if (_activeSubTab == tab) return;
    _activeSubTab = tab;
    notifyListeners();
  }

  void selectRequest(GoodMoralRequestModel request) {
    _selectedStudentRequest = GoodMoralSelectedStudent.fromRequest(request);
    notifyListeners();
  }

  void selectStudent(StudentDirectoryEntryModel student) {
    _selectedStudentRequest = GoodMoralSelectedStudent.fromDirectoryEntry(
      student,
    );
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedStudentRequest == null) return;
    _selectedStudentRequest = null;
    notifyListeners();
  }

  void setRequests(List<GoodMoralRequestModel> requests) {
    _requests = requests;
    _refreshSelectionIfStale();
    notifyListeners();
  }

  void setStudents(List<StudentDirectoryEntryModel> students) {
    _students = students;
    _refreshSelectionIfStale();
    notifyListeners();
  }

  /// Re-derives the current selection from the freshly-loaded [_requests] /
  /// [_students] list it came from, so a live reload (e.g. a violation
  /// getting resolved/archived elsewhere) updates the Preview panel's
  /// Clearance Status banner for whichever student is currently open instead
  /// of leaving it showing stale data until the officer re-selects them.
  /// Leaves the selection untouched if its source row is no longer present.
  void _refreshSelectionIfStale() {
    final current = _selectedStudentRequest;
    if (current == null) return;

    if (current.sourceSubTab == GoodMoralSubTab.requests) {
      for (final request in _requests) {
        if (request.id == current.sourceId) {
          _selectedStudentRequest =
              GoodMoralSelectedStudent.fromRequest(request);
          return;
        }
      }
    } else {
      for (final student in _students) {
        if (student.id == current.sourceId) {
          _selectedStudentRequest =
              GoodMoralSelectedStudent.fromDirectoryEntry(student);
          return;
        }
      }
    }
  }
}
