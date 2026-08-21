import 'package:discipline_officer_module/discipline_officer_module.dart'
    show OffenseOption;
import 'package:flutter/material.dart';
import 'package:kiosk/kiosk_module.dart';
import 'package:student_kiosk_module/student_kiosk.dart';
import 'package:student_kiosk_module/theme/kiosk_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

import '../data/discipline_repository.dart';
import '../data/students_repository.dart';
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
  DisciplineRepository? get _disciplineRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
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

  Future<void> _submitViolations(
    BuildContext ctx,
    KioskStudentPayload student,
    List<OffenseOption> offenseOptions,
    List<String> selectedOffenseIds,
  ) async {
    final repo = _disciplineRepo;
    if (repo == null) {
      throw Exception('Supabase is not configured.');
    }

    await Supabase.instance.client.from('student_violations').insert([
      for (final offenseId in selectedOffenseIds)
        {
          'student_id': student.id,
          'offense_id': offenseId,
          'reported_by': _kioskReporterProfileId,
          'status': 'Pending',
        },
    ]);

    if (!ctx.mounted) return;

    final selectedLabels = [
      for (final offenseId in selectedOffenseIds)
        offenseOptions
            .firstWhere(
              (o) => o.id == offenseId,
              orElse: () => OffenseOption(id: offenseId, label: offenseId),
            )
            .label,
    ];

    final now = DateTime.now();
    final validUntil = now.add(const Duration(hours: 72));
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (_) => AdmissionSlipGeneratedView(
          data: AdmissionSlipData(
            studentName: student.displayName,
            studentNumber: student.studentNumber,
            gradeSection: student.gradeSection ?? '{{gradeSection}}',
            slipId: 'VAS-${student.studentNumber}-${now.millisecondsSinceEpoch}',
            violationCode: '${selectedOffenseIds.length} violation'
                '${selectedOffenseIds.length == 1 ? '' : 's'} acknowledged',
            violationDescription: selectedLabels.join(', '),
            issueDateTime: _formatDateTime(now),
            validUntil: _formatDateTime(validUntil),
            timeRemaining: '72 hours',
          ),
        ),
      ),
    );
  }

  Future<void> _submitSecurityReport(
    BuildContext ctx,
    String officerId,
    SecurityReportSubmission submission,
  ) async {
    if (!AppEnv.supabaseConfigured) {
      throw Exception('Supabase is not configured.');
    }
    await Supabase.instance.client.from('student_violations').insert([
      for (final offenseId in submission.offenseIds)
        {
          'student_id': submission.studentId,
          'offense_id': offenseId,
          'reported_by': officerId,
          'status': 'Pending',
          'is_escalated': submission.escalateNow,
          if (submission.notes.isNotEmpty) 'incident_notes': submission.notes,
        },
    ]);
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
              onSubmit: (submission) =>
                  _submitSecurityReport(ctx, staff.id, submission),
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
              onConfirm: (selectedCodes) => _submitViolations(
                ctx,
                payload,
                offenseOptions,
                selectedCodes,
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
