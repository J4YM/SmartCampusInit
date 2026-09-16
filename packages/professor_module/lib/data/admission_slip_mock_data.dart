import '../pages/dashboard/admission_slip_view.dart';

/// Demo content for the Admission Slip tab — lets this package stay
/// independently runnable/demoable before the real `admission_slips` /
/// `student_violations` Supabase tables are wired up for this tab.
abstract final class AdmissionSlipMockData {
  static List<AdmissionSlipModel> getSlips() => [
        AdmissionSlipModel(
          id: 'as1',
          studentName: 'Juan Dela Cruz',
          studentNumber: '02000123456',
          section: 'BSIT - 4B',
          submittedAt: DateTime(2026, 9, 15, 8, 12),
          status: AdmissionSlipStatus.pending,
          violations: const [
            AdmissionSlipViolationEntry(
              offenseLabel: 'Improper uniform (untucked shirt)',
              category: 'Minor',
            ),
            AdmissionSlipViolationEntry(
              offenseLabel: 'Missing ID/nameplate',
              category: 'Minor',
            ),
          ],
        ),
        AdmissionSlipModel(
          id: 'as2',
          studentName: 'Patricia Cruz',
          studentNumber: '02000123426',
          section: 'BSIT - 3B',
          submittedAt: DateTime(2026, 9, 15, 7, 48),
          status: AdmissionSlipStatus.approved,
          violations: const [
            AdmissionSlipViolationEntry(
              offenseLabel: 'Late arrival (within 15 minutes)',
              category: 'Minor',
            ),
          ],
        ),
        AdmissionSlipModel(
          id: 'as3',
          studentName: 'Michael Santos',
          studentNumber: '02000123423',
          section: 'BSTM - 2A',
          submittedAt: DateTime(2026, 9, 14, 9, 5),
          status: AdmissionSlipStatus.declined,
          violations: const [
            AdmissionSlipViolationEntry(
              offenseLabel: 'Unauthorized hair color',
              category: 'Minor',
            ),
            AdmissionSlipViolationEntry(
              offenseLabel: 'Improper shoes',
              category: 'Minor',
            ),
          ],
        ),
        AdmissionSlipModel(
          id: 'as4',
          studentName: 'Jericho Clemente',
          studentNumber: '02000128992',
          section: 'BSBA - 1A',
          submittedAt: DateTime(2026, 9, 13, 13, 20),
          status: AdmissionSlipStatus.pending,
          violations: const [
            AdmissionSlipViolationEntry(
              offenseLabel: 'Incomplete requirements',
              category: 'Other',
            ),
          ],
        ),
      ];
}
