import 'package:discipline_officer_module/discipline_officer_module.dart'
    show OffenseOption;
import 'package:flutter/material.dart';
import 'package:kiosk/kiosk_module.dart';
import 'package:student_kiosk_module/student_kiosk.dart';
import 'package:student_kiosk_module/theme/kiosk_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

import '../data/admission_slip_repository.dart';
import '../data/discipline_repository.dart';
import '../data/students_repository.dart';
import '../documents/admission_slip_pdf.dart';
import '../env.dart';
import 'security_report_screen.dart';

/// System profile that stands in for `student_violations.reported_by` when a
/// violation is self-reported at the kiosk (RFID tap only — no staff member
/// is authenticated alongside the student). Seeded by
/// supabase/add_kiosk_violation_insert_schema.sql; must match that file's
/// literal id.
const String _kioskReporterProfileId = '00000000-0000-4000-8000-000000000001';

/// Wires [VirtualAdmissionKioskScreen] to Supabase, the real violation
/// picker ([ViolationKioskScreen], populated from `handbook_offenses`), and
/// the Virtual Admission Slip UI.
class CapstoneKioskScanHost extends StatefulWidget {
  const CapstoneKioskScanHost({
    super.key,
    this.embedFromHub = false,
  });

  /// When true, shows a back control for returning to the admin hub.
  final bool embedFromHub;

  @override
  State<CapstoneKioskScanHost> createState() => _CapstoneKioskScanHostState();
}

class _CapstoneKioskScanHostState extends State<CapstoneKioskScanHost> {
  static const _uuid = Uuid();

  DisciplineRepository? get _disciplineRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
  }

  AdmissionSlipRepository? get _slipRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return AdmissionSlipRepository(Supabase.instance.client);
  }

  /// Cached across scans so re-opening the violation picker doesn't refetch
  /// `handbook_offenses` every tap. `null` until first loaded (or if it
  /// couldn't be loaded — the picker then falls back to its own demo list).
  List<OffenseOption>? _offenseOptionsCache;

  Future<List<OffenseOption>> _loadOffenseOptions() async {
    final cached = _offenseOptionsCache;
    if (cached != null) return cached;
    final repo = _disciplineRepo;
    if (repo == null) return const [];
    try {
      final options = await repo.fetchOffenseOptions();
      _offenseOptionsCache = options;
      return options;
    } catch (_) {
      return const [];
    }
  }

  /// Shared by both the student self-report path and the Security
  /// Personnel report path — nothing is written to the database yet at
  /// this point. Pushes the preview screen with a client-generated slip id
  /// (so its QR code is already valid) and only writes on Confirm/Confirm &
  /// Print, via [AdmissionSlipRepository.submit]'s single-transaction RPC.
  void _openSlipPreview(
    BuildContext ctx, {
    required String studentId,
    required String studentDisplayName,
    required String studentNumber,
    required String gradeSection,
    required List<OffenseOption> offenseOptions,
    required List<String> selectedOffenseIds,
    required String reportedBy,
    bool isEscalated = false,
    String? notes,
  }) {
    final slipId = _uuid.v4();
    final now = DateTime.now();
    final validUntil = now.add(const Duration(hours: 72));
    final selectedLabels = [
      for (final offenseId in selectedOffenseIds)
        offenseOptions
            .firstWhere(
              (o) => o.id == offenseId,
              orElse: () => OffenseOption(id: offenseId, label: offenseId),
            )
            .label,
    ];

    final data = AdmissionSlipData(
      studentName: studentDisplayName,
      studentNumber: studentNumber,
      gradeSection: gradeSection,
      slipId: slipId,
      violationCode: '${selectedOffenseIds.length} violation'
          '${selectedOffenseIds.length == 1 ? '' : 's'} acknowledged',
      violationDescription: selectedLabels.join(', '),
      issueDateTime: _formatDateTime(now),
      validUntil: _formatDateTime(validUntil),
      timeRemaining: '72 hours',
      qrUrl: AppEnv.slipBaseUrl.isEmpty
          ? ''
          : '${AppEnv.slipBaseUrl}/slip/$slipId',
    );

    Future<void> confirm() async {
      final repo = _slipRepo;
      if (repo == null) {
        throw Exception('Supabase is not configured.');
      }
      await repo.submit(
        AdmissionSlipSubmission(
          slipId: slipId,
          studentId: studentId,
          reportedBy: reportedBy,
          offenseIds: selectedOffenseIds,
          isEscalated: isEscalated,
          notes: notes,
        ),
      );
    }

    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (_) => AdmissionSlipPreviewScreen(
          data: data,
          onCancel: () => Navigator.of(ctx).pop(),
          onConfirm: confirm,
          onConfirmAndPrint: confirm,
          onPrint: () => silentPrintAdmissionSlip(data),
          onDone: () {
            // This flow always pushes exactly two screens on top of the
            // idle scan screen — the offense-picker/report screen, then
            // this preview — regardless of whether the kiosk itself is the
            // app's root (standalone build) or was pushed from the Admin
            // Hub (embedFromHub). Popping a fixed count back to "wherever
            // we started" is robust to both; popUntil(isFirst) would be
            // wrong for the embedded case (it'd pop past the Hub too).
            final navigator = Navigator.of(ctx);
            navigator.pop(); // this preview screen
            navigator.pop(); // the offense-picker / report screen
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = VirtualAdmissionKioskScreen(
      identifyStudent: (uid) async {
        if (!AppEnv.supabaseConfigured) return null;
        final repo = StudentsRepository(Supabase.instance.client);
        final student = await repo.fetchStudentByRfidUid(uid);
        if (student == null) return null;
        return KioskStudentPayload(
          id: student.id,
          displayName: student.fullName,
          studentNumber: student.studentNumber,
          gradeSection: '${student.yearLevel} — ${student.section}',
          course: student.course,
        );
      },
      identifyStaff: (uid) async {
        if (!AppEnv.supabaseConfigured) return null;
        final repo = StudentsRepository(Supabase.instance.client);
        final staff = await repo.fetchStaffByRfidCardId(uid);
        if (staff == null) return null;
        return KioskStaffPayload(
          id: staff.id,
          displayName: staff.fullName,
          roleLabel: staff.role,
        );
      },
      onStaffIdentified: (ctx, staff) async {
        if (staff.roleLabel != 'Security') {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                'This kiosk does not have a reporting flow for '
                '${staff.roleLabel} yet.',
              ),
            ),
          );
          return;
        }

        final offenseOptions = await _loadOffenseOptions();
        if (!ctx.mounted) return;
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => SecurityReportScreen(
              officerName: staff.displayName,
              offenseOptions: offenseOptions,
              onSearchStudents: (query) async {
                final repo = StudentsRepository(Supabase.instance.client);
                final results =
                    await repo.searchByStudentNumberPrefix(query);
                return [
                  for (final s in results)
                    SecurityReportStudentOption(
                      id: s.id,
                      displayName: s.fullName,
                      studentNumber: s.studentNumber,
                      gradeSection: '${s.yearLevel} — ${s.section}',
                    ),
                ];
              },
              onSubmit: (submission) => _openSlipPreview(
                ctx,
                studentId: submission.studentId,
                studentDisplayName: submission.studentDisplayName,
                studentNumber: submission.studentNumber,
                gradeSection: submission.gradeSection,
                offenseOptions: offenseOptions,
                selectedOffenseIds: submission.offenseIds,
                reportedBy: staff.id,
                isEscalated: submission.escalateNow,
                notes: submission.notes,
              ),
            ),
          ),
        );
      },
      onStudentIdentified: (ctx, payload) async {
        final offenseOptions = await _loadOffenseOptions();
        if (!ctx.mounted) return;
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => ViolationKioskScreen(
              studentName: payload.displayName,
              studentId: payload.studentNumber,
              categories: offenseOptions.isEmpty
                  ? null
                  : _groupOffensesByCategory(offenseOptions),
              onConfirm: (selectedCodes) async => _openSlipPreview(
                ctx,
                studentId: payload.id,
                studentDisplayName: payload.displayName,
                studentNumber: payload.studentNumber,
                gradeSection: payload.gradeSection ?? '{{gradeSection}}',
                offenseOptions: offenseOptions,
                selectedOffenseIds: selectedCodes,
                reportedBy: _kioskReporterProfileId,
              ),
            ),
          ),
        );
      },
    );

    late final Widget body;
    if (!AppEnv.supabaseConfigured) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Material(
            color: Color(0xFFFEF3C7),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Supabase is not configured (.env or dart-define). '
                'RFID lookup cannot run on this kiosk build.',
                style: TextStyle(color: Color(0xFF92400E), fontSize: 13),
              ),
            ),
          ),
          Expanded(child: scan),
        ],
      );
    } else {
      body = scan;
    }

    if (!widget.embedFromHub) {
      return body;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: 'Back to hub',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Groups `handbook_offenses` rows (as [OffenseOption]s) by their severity
/// category into the picker's [ViolationCategoryData] shape, in ascending
/// severity order.
List<ViolationCategoryData> _groupOffensesByCategory(
  List<OffenseOption> options,
) {
  const categoryOrder = ['Minor', 'Major_A', 'Major_B', 'Major_C', 'Major_D'];
  final byCategory = <String, List<OffenseOption>>{};
  for (final option in options) {
    final category = option.category ?? 'Minor';
    byCategory.putIfAbsent(category, () => []).add(option);
  }

  return [
    for (final category in categoryOrder)
      if (byCategory[category] case final items? when items.isNotEmpty)
        ViolationCategoryData(
          badgeLabel: _categoryBadgeLabel(category),
          badgeBackground: _categoryBadgeBackground(category),
          badgeForeground: _categoryBadgeForeground(category),
          items: [
            for (final option in items)
              ViolationItemData(title: option.label, code: option.id),
          ],
        ),
  ];
}

String _categoryBadgeLabel(String category) {
  return switch (category) {
    'Minor' => 'Minor Offense',
    'Major_A' => 'Major Offense — Category A',
    'Major_B' => 'Major Offense — Category B',
    'Major_C' => 'Major Offense — Category C',
    'Major_D' => 'Major Offense — Category D',
    _ => category,
  };
}

Color _categoryBadgeBackground(String category) {
  return switch (category) {
    'Minor' => KioskColors.minorBadgeBg,
    'Major_A' => KioskColors.majorABadgeBg,
    'Major_B' => KioskColors.majorBBadgeBg,
    'Major_C' => KioskColors.majorCBadgeBg,
    'Major_D' => KioskColors.majorDBadgeBg,
    _ => KioskColors.otherBadgeBg,
  };
}

Color _categoryBadgeForeground(String category) {
  return switch (category) {
    'Minor' => KioskColors.minorBadgeFg,
    'Major_A' => KioskColors.majorABadgeFg,
    'Major_B' => KioskColors.majorBBadgeFg,
    'Major_C' => KioskColors.majorCBadgeFg,
    'Major_D' => KioskColors.majorDBadgeFg,
    _ => KioskColors.otherBadgeFg,
  };
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day ${h.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
}
