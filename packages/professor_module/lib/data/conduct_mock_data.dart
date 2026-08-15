import '../pages/dashboard/conduct_report_view.dart';

/// Demo content lifted from the Figma "PROF | Overview — Conduct Report"
/// frame — lets this package stay independently runnable/demoable before
/// the real `students` / `student_violations` Supabase tables are wired up
/// for this module.
abstract final class ConductMockData {
  static List<ConductStudentModel> getStudents() => const [
        ConductStudentModel(
          id: 'cs1',
          name: 'Juan Dela Cruz',
          section: 'BSIT - 4B',
          studentNumber: '02000123456',
          previousViolationsCount: 4,
        ),
        ConductStudentModel(
          id: 'cs2',
          name: 'Patricia Cruz',
          section: 'BSIT - 3B',
          studentNumber: '02000123426',
        ),
        ConductStudentModel(
          id: 'cs3',
          name: 'Michael Santos',
          section: 'BSTM - 2A',
          studentNumber: '02000123423',
        ),
        ConductStudentModel(
          id: 'cs4',
          name: 'Jericho Clemente',
          section: 'BSBA - 1A',
          studentNumber: '02000128992',
        ),
        ConductStudentModel(
          id: 'cs5',
          name: 'Jade Marie Montalban',
          section: 'BSHM - 4B',
          studentNumber: '02000156125',
        ),
        ConductStudentModel(
          id: 'cs6',
          name: 'Shayne Mae Pinto',
          section: 'BSHM - 3A',
          studentNumber: '02000653998',
        ),
        ConductStudentModel(
          id: 'cs7',
          name: 'Leon Paul Rosales',
          section: 'BSBA - 3A',
          studentNumber: '02000653298',
        ),
        ConductStudentModel(
          id: 'cs8',
          name: 'Leon Paul Rosales',
          section: 'BSBA - 3A',
          studentNumber: '02000653298',
        ),
      ];

  static ConductOffenseSummaryModel getOffenseSummary() =>
      const ConductOffenseSummaryModel();

  static List<ConductViolationOption> getViolationOptions() => const [
        ConductViolationOption(id: 'v1', label: 'Minor – Tardiness'),
        ConductViolationOption(id: 'v2', label: 'Minor – Uniform Violation'),
        ConductViolationOption(
          id: 'v3',
          label: 'Minor – Unauthorized Use of Mobile Phone',
        ),
        ConductViolationOption(
          id: 'v4',
          label: 'Major – Academic Dishonesty',
        ),
        ConductViolationOption(id: 'v5', label: 'Major – Bullying/Harassment'),
        ConductViolationOption(id: 'v6', label: 'Major – Vandalism'),
      ];
}
