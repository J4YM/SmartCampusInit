import '../pages/dashboard/discipline_officer_dashboard_page.dart';

/// Static mock/demo dataset for the Discipline Officer Dashboard — fills the
/// Violations queue, Good Moral Management queue/directory, and the summary
/// metric cards with realistic sample records while the real Supabase
/// integration (see the `TODO(supabase)` markers throughout
/// `discipline_officer_dashboard_page.dart`) isn't wired up yet.
///
/// Returns the dashboard's own model types directly (`DisciplineCaseModel`,
/// `GoodMoralRequestModel`, `StudentDirectoryEntryModel`,
/// `DisciplineSummaryMetricsModel`) so callers can drop the results straight
/// into the page's state, e.g.:
/// ```dart
/// pendingQueue.addAll(DisciplineOfficerMockData.getPendingViolations());
/// metrics = DisciplineOfficerMockData.getSummaryMetrics();
/// goodMoralController.setRequests(DisciplineOfficerMockData.getGoodMoralRequests());
/// goodMoralController.setStudents(DisciplineOfficerMockData.getStudentDirectory());
/// ```
///
/// There's no dedicated `ViolationCaseModel`/`GoodMoralRequestModel` pair
/// scoped to this file — the dashboard already defines those model classes
/// (with `fromJson`/`toJson` mapped to the planned Postgres schema), and
/// duplicating them here under the same names would collide when both files
/// are imported together. Fields the dashboard's models don't carry yet
/// (offense severity, clearance status, offense-count breakdown) are folded
/// into existing free-text fields (`violationType`, `remarks`) instead of
/// growing the models for a mock-only concern.
abstract final class DisciplineOfficerMockData {
  static final DateTime _now = DateTime.now();

  /// Stat-card metrics matching [getPendingViolations] — 2 escalated of 6
  /// pending, plus a plausible day-so-far processed count and average
  /// response time.
  static DisciplineSummaryMetricsModel getSummaryMetrics() {
    return const DisciplineSummaryMetricsModel(
      pendingQueueCount: 6,
      escalatedCount: 2,
      processedTodayCount: 9,
      avgResponseTimeMinutes: 34.5,
    );
  }

  /// Active (pending/escalated) violation cases for the Approval Queue and
  /// Incident Details panel. Only pending/escalated records are generated —
  /// once a case is Approved/Modified/Denied the dashboard removes it from
  /// `pendingQueue` rather than tracking a "processed"/"denied" status, so
  /// mock records for those states would have nowhere to render.
  static List<DisciplineCaseModel> getPendingViolations() {
    return [
      DisciplineCaseModel(
        id: 'VIO-2031',
        studentName: 'Miguel Dela Cruz',
        studentNumber: '22-10456',
        programGradeSection: 'BSIT 3-A',
        violationType: 'Major – Academic Dishonesty',
        isEscalated: true,
        slaRemaining: '00:45',
        submittedBy: 'Prof. R. Santos',
        incidentLocation: 'IT Laboratory 3',
        incidentDateTime: _now.subtract(const Duration(hours: 2, minutes: 10)),
        priorViolationsCount: 2,
        description:
            'Caught using an unauthorized reviewer app during the midterm '
            'practical exam.',
      ),
      DisciplineCaseModel(
        id: 'VIO-2032',
        studentName: 'Andrea Bautista',
        studentNumber: '23-10789',
        programGradeSection: 'BSBA 2-C',
        violationType: 'Minor – Uniform Violation',
        isEscalated: false,
        slaRemaining: '05:30',
        submittedBy: 'Guard J. De Leon',
        incidentLocation: 'Main Gate',
        incidentDateTime: _now.subtract(const Duration(hours: 4, minutes: 5)),
        priorViolationsCount: 0,
        description: 'Reported to campus without the prescribed uniform.',
      ),
      DisciplineCaseModel(
        id: 'VIO-2033',
        studentName: 'Josh Villanueva',
        studentNumber: '21-10233',
        programGradeSection: 'BSCpE 4-B',
        violationType: 'Major – Vandalism',
        isEscalated: true,
        slaRemaining: '01:15',
        submittedBy: 'Prof. L. Villanueva',
        incidentLocation: 'Engineering Workshop',
        incidentDateTime: _now.subtract(const Duration(hours: 1, minutes: 30)),
        priorViolationsCount: 1,
        description:
            'Damaged laboratory equipment and left graffiti on a workstation '
            'panel.',
      ),
      DisciplineCaseModel(
        id: 'VIO-2034',
        studentName: 'Kimberly Santos',
        studentNumber: '22-10998',
        programGradeSection: 'BSIT 1-D',
        violationType: 'Minor – Late Return of Equipment',
        isEscalated: false,
        slaRemaining: null,
        submittedBy: 'Ms. A. Reyes (Property Custodian)',
        incidentLocation: 'IT Laboratory 1',
        incidentDateTime: _now.subtract(const Duration(hours: 20)),
        priorViolationsCount: 0,
        description:
            'Borrowed a laptop cart unit for a project demo and returned it '
            'three days past the due date.',
      ),
      DisciplineCaseModel(
        id: 'VIO-2035',
        studentName: 'Rafael Mercado',
        studentNumber: '20-10087',
        programGradeSection: 'BSA 3-A',
        violationType: 'Minor – Unauthorized Use of Mobile Phone',
        isEscalated: false,
        slaRemaining: '07:00',
        submittedBy: 'Prof. C. Ramos',
        incidentLocation: 'Main Building – Room 204',
        incidentDateTime: _now.subtract(const Duration(minutes: 40)),
        priorViolationsCount: 1,
        description: 'Used a mobile phone to answer a graded quiz.',
      ),
      DisciplineCaseModel(
        id: 'VIO-2036',
        studentName: 'Angel Reyes',
        studentNumber: '23-10345',
        programGradeSection: 'BSBA 1-A',
        violationType: 'Major – Bullying/Harassment',
        isEscalated: true,
        slaRemaining: '02:50',
        submittedBy: 'Ms. P. Fernandez (Guidance)',
        incidentLocation: 'Canteen',
        incidentDateTime: _now.subtract(const Duration(hours: 6)),
        priorViolationsCount: 0,
        description:
            'Multiple classmates reported repeated verbal harassment during '
            'lunch break.',
      ),
    ];
  }

  /// Pending Good Moral / Clearance requests for the Requests Queue tab and
  /// the right-hand evaluation preview. `remarks` carries the clearance
  /// summary (major/minor offense counts, sanctions status) since that's the
  /// one free-text field the preview panel already renders — see
  /// `_GoodMoralPreviewDetails` in the dashboard page.
  static List<GoodMoralRequestModel> getGoodMoralRequests() {
    return [
      GoodMoralRequestModel(
        id: 'GMR-1041',
        studentName: 'Precious Aquino',
        studentNumber: '21-10456',
        programGradeSection: 'BSIT 4-A',
        documentType: 'Good Moral Certificate',
        purpose: 'Employment application',
        requestedBy: 'Precious Aquino',
        requestDateTime: _now.subtract(const Duration(hours: 3)),
        remarks: _clearanceRemarks(
          clearanceStatus: 'Eligible',
          majorOffenses: 0,
          minorOffenses: 0,
          sanctionsCleared: true,
        ),
      ),
      GoodMoralRequestModel(
        id: 'GMR-1042',
        studentName: 'Nathaniel Cruz',
        studentNumber: '22-10118',
        programGradeSection: 'BSCpE 2-B',
        documentType: 'Certificate of Clearance',
        purpose: 'School transfer',
        requestedBy: 'Nathaniel Cruz',
        requestDateTime: _now.subtract(const Duration(hours: 26)),
        remarks: _clearanceRemarks(
          clearanceStatus: 'Conditional',
          majorOffenses: 0,
          minorOffenses: 2,
          sanctionsCleared: false,
        ),
      ),
      GoodMoralRequestModel(
        id: 'GMR-1043',
        studentName: 'Bianca Torres',
        studentNumber: '20-10902',
        programGradeSection: 'BSA 4-C',
        documentType: 'Good Moral Certificate',
        purpose: 'Scholarship application',
        requestedBy: 'Bianca Torres',
        requestDateTime: _now.subtract(const Duration(hours: 8)),
        remarks: _clearanceRemarks(
          clearanceStatus: 'Eligible',
          majorOffenses: 0,
          minorOffenses: 0,
          sanctionsCleared: true,
        ),
      ),
      GoodMoralRequestModel(
        id: 'GMR-1044',
        studentName: 'Josh Villanueva',
        studentNumber: '21-10233',
        programGradeSection: 'BSCpE 4-B',
        documentType: 'Good Moral Certificate',
        purpose: 'Graduation requirement',
        requestedBy: 'Josh Villanueva',
        requestDateTime: _now.subtract(const Duration(hours: 50)),
        remarks: _clearanceRemarks(
          clearanceStatus: 'Ineligible',
          majorOffenses: 1,
          minorOffenses: 1,
          sanctionsCleared: false,
        ),
      ),
      GoodMoralRequestModel(
        id: 'GMR-1045',
        studentName: 'Samantha Lopez',
        studentNumber: '23-10560',
        programGradeSection: 'BSBA 3-B',
        documentType: 'Certificate of Clearance',
        purpose: 'Employment application',
        requestedBy: 'Samantha Lopez',
        requestDateTime: _now.subtract(const Duration(hours: 12)),
        remarks: _clearanceRemarks(
          clearanceStatus: 'Eligible',
          majorOffenses: 0,
          minorOffenses: 1,
          sanctionsCleared: true,
        ),
      ),
      GoodMoralRequestModel(
        id: 'GMR-1046',
        studentName: 'Christian Domingo',
        studentNumber: '22-10671',
        programGradeSection: 'BSIT 2-A',
        documentType: 'Good Moral Certificate',
        purpose: 'Scholarship application',
        requestedBy: 'Christian Domingo',
        requestDateTime: _now.subtract(const Duration(hours: 30)),
        remarks: _clearanceRemarks(
          clearanceStatus: 'Conditional',
          majorOffenses: 0,
          minorOffenses: 1,
          sanctionsCleared: false,
        ),
      ),
    ];
  }

  /// Master student directory for the Good Moral Management "Students List"
  /// tab — a mix of students with and without an active clearance request on
  /// file, so the queue/directory views don't look like mirrors of each
  /// other.
  static List<StudentDirectoryEntryModel> getStudentDirectory() {
    return [
      const StudentDirectoryEntryModel(
        id: 'STU-10456',
        studentName: 'Precious Aquino',
        studentNumber: '21-10456',
        programGradeSection: 'BSIT 4-A',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10118',
        studentName: 'Nathaniel Cruz',
        studentNumber: '22-10118',
        programGradeSection: 'BSCpE 2-B',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10902',
        studentName: 'Bianca Torres',
        studentNumber: '20-10902',
        programGradeSection: 'BSA 4-C',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10233',
        studentName: 'Josh Villanueva',
        studentNumber: '21-10233',
        programGradeSection: 'BSCpE 4-B',
        status: 'On Probation',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10456B',
        studentName: 'Miguel Dela Cruz',
        studentNumber: '22-10456',
        programGradeSection: 'BSIT 3-A',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10789',
        studentName: 'Andrea Bautista',
        studentNumber: '23-10789',
        programGradeSection: 'BSBA 2-C',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10345',
        studentName: 'Angel Reyes',
        studentNumber: '23-10345',
        programGradeSection: 'BSBA 1-A',
      ),
      const StudentDirectoryEntryModel(
        id: 'STU-10087',
        studentName: 'Rafael Mercado',
        studentNumber: '20-10087',
        programGradeSection: 'BSA 3-A',
      ),
    ];
  }

  static String _clearanceRemarks({
    required String clearanceStatus,
    required int majorOffenses,
    required int minorOffenses,
    required bool sanctionsCleared,
  }) {
    return 'Clearance status: $clearanceStatus\n'
        'Major offenses on record: $majorOffenses\n'
        'Minor offenses on record: $minorOffenses\n'
        'Sanctions cleared: ${sanctionsCleared ? 'Yes' : 'No'}';
  }
}
