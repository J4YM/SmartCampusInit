import 'package:flutter/material.dart';

import '../models/violation_models.dart';
import '../theme/kiosk_colors.dart';
import '../widgets/kiosk_layout.dart';

export '../models/violation_models.dart';

class ViolationKioskScreen extends StatefulWidget {
  const ViolationKioskScreen({
    super.key,
    this.studentName = '',
    this.studentId = '',
    this.categories,
    this.teachers,
    this.onConfirm,
  });

  /// Full name shown in the student card; when empty, a muted placeholder is shown.
  final String studentName;

  /// Student number/id shown after "Student No: "; when empty, a muted placeholder is shown.
  final String studentId;

  /// Violation choices to show, grouped by category. Defaults to
  /// [_demoCategories] (a fixed demo taxonomy) so this screen stays
  /// demoable standalone; a connected host should pass real
  /// `handbook_offenses` rows instead (see `lib/kiosk/capstone_kiosk_scan_host.dart`),
  /// with [ViolationItemData.code] set to each offense's `id`.
  final List<ViolationCategoryData>? categories;

  /// "Teacher / Adviser" dropdown options. Defaults to [_demoTeacherOptions]
  /// (a fixed demo roster) so this screen stays demoable standalone; a
  /// connected host should pass real `profiles` (role `Teacher`) rows
  /// instead, matching `RegistrarRepository.fetchTeachers()`.
  final List<TeacherOptionData>? teachers;

  /// Called with the selected [ViolationItemData.code]s and the selected
  /// teacher's id (null if none was picked — this dropdown isn't required)
  /// when "Confirm & Generate Slip" is tapped. When omitted, the button is
  /// a no-op (demo behavior). Any thrown error is shown as a snackbar and
  /// the selection is preserved so the user can retry.
  final Future<void> Function(List<String> selectedCodes, String? professorId)?
      onConfirm;

  @override
  State<ViolationKioskScreen> createState() => _ViolationKioskScreenState();
}

class _ViolationKioskScreenState extends State<ViolationKioskScreen> {
  final Set<String> _selectedCodes = {};
  bool _confirming = false;
  String? _selectedTeacherId;

  /// Placeholder roster — a connected host should pass real teacher/adviser
  /// rows instead once this dropdown is wired to something.
  static const List<TeacherOptionData> _demoTeacherOptions = [
    TeacherOptionData(id: 'demo-1', fullName: 'Mr. Juan Dela Cruz'),
    TeacherOptionData(id: 'demo-2', fullName: 'Ms. Maria Santos'),
    TeacherOptionData(id: 'demo-3', fullName: 'Mr. Jose Rizal'),
    TeacherOptionData(id: 'demo-4', fullName: 'Ms. Ana Lim'),
    TeacherOptionData(id: 'demo-5', fullName: 'Mr. Carlos Reyes'),
  ];

  static const List<ViolationCategoryData> _demoCategories = [
    ViolationCategoryData(
      badgeLabel: 'Uniform Violation',
      badgeBackground: KioskColors.uniformBadgeBg,
      badgeForeground: KioskColors.uniformBadgeFg,
      items: [
        ViolationItemData(
          title: 'Improper uniform (untucked shirt)',
          code: 'UNI-001',
        ),
        ViolationItemData(title: 'Missing ID/nameplate', code: 'UNI-002'),
        ViolationItemData(title: 'Improper shoes', code: 'UNI-003'),
        ViolationItemData(title: 'Unauthorized accessories', code: 'UNI-004'),
      ],
    ),
    ViolationCategoryData(
      badgeLabel: 'Grooming Violation',
      badgeBackground: KioskColors.groomingBadgeBg,
      badgeForeground: KioskColors.groomingBadgeFg,
      items: [
        ViolationItemData(title: 'Improper haircut/hairstyle', code: 'GRO-001'),
        ViolationItemData(title: 'Unauthorized hair color', code: 'GRO-002'),
      ],
    ),
    ViolationCategoryData(
      badgeLabel: 'Punctuality',
      badgeBackground: KioskColors.punctualityBadgeBg,
      badgeForeground: KioskColors.punctualityBadgeFg,
      items: [
        ViolationItemData(
          title: 'Late arrival (within 15 minutes)',
          code: 'PUN-001',
        ),
      ],
    ),
    ViolationCategoryData(
      badgeLabel: 'Other',
      badgeBackground: KioskColors.otherBadgeBg,
      badgeForeground: KioskColors.otherBadgeFg,
      items: [
        ViolationItemData(title: 'Incomplete requirements', code: 'OTH-001'),
        ViolationItemData(title: 'No written excuse', code: 'OTH-002'),
      ],
    ),
  ];

  void _toggleCode(String code) {
    setState(() {
      if (_selectedCodes.contains(code)) {
        _selectedCodes.remove(code);
      } else {
        _selectedCodes.add(code);
      }
    });
  }

  Future<void> _handleConfirm() async {
    if (_selectedCodes.isEmpty || _confirming || widget.onConfirm == null) {
      return;
    }
    setState(() => _confirming = true);
    try {
      await widget.onConfirm!(_selectedCodes.toList(), _selectedTeacherId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit: $e')),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedCodes.length;
    final categories = widget.categories ?? _demoCategories;
    final teacherOptions = widget.teachers ?? _demoTeacherOptions;

    return KioskPage(
      children: [
        _StudentInfoCard(
          studentName: widget.studentName,
          studentId: widget.studentId,
        ),
        const SizedBox(height: 20),
        _TeacherDropdownCard(
          teachers: teacherOptions,
          value: _selectedTeacherId,
          onChanged: (value) {
            setState(() => _selectedTeacherId = value);
          },
        ),
        const SizedBox(height: 20),
        const KioskInstructionAlert(
          title: 'Please select your violation(s)',
          body: 'Select all violations that apply to you. You must acknowledge '
              'your violations to proceed.',
        ),
        const SizedBox(height: 20),
        for (final cat in categories) ...[
          KioskViolationCategoryCard(
            category: cat,
            selectedCodes: _selectedCodes,
            onToggle: _toggleCode,
          ),
          const SizedBox(height: 20),
        ],
        KioskSelectedCountCard(
          selectedCount: selectedCount,
          caption:
              'Review your selection and confirm to generate admission slip',
        ),
        const SizedBox(height: 16),
        KioskConfirmButton(
          label: 'Confirm & Generate Slip',
          enabled: selectedCount > 0 && !_confirming,
          busy: _confirming,
          onPressed:
              selectedCount == 0 || _confirming ? null : _handleConfirm,
        ),
      ],
    );
  }
}

class _StudentInfoCard extends StatelessWidget {
  const _StudentInfoCard({
    required this.studentName,
    required this.studentId,
  });

  final String studentName;
  final String studentId;

  static const String _emptyPlaceholder = '—';

  @override
  Widget build(BuildContext context) {
    final name = studentName.trim();
    final id = studentId.trim();
    final nameDisplay = name.isNotEmpty ? name : _emptyPlaceholder;
    final idDisplay = id.isNotEmpty ? id : _emptyPlaceholder;

    return KioskCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameDisplay,
                  style: kioskPoppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: name.isNotEmpty
                        ? KioskColors.textPrimary
                        : KioskColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: kioskPoppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: KioskColors.textSecondary,
                    ),
                    children: [
                      const TextSpan(text: 'Student No: '),
                      TextSpan(
                        text: idDisplay,
                        style: TextStyle(
                          color: id.isNotEmpty
                              ? KioskColors.textSecondary
                              : KioskColors.textMuted,
                          fontWeight:
                              id.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const KioskBackButton(),
        ],
      ),
    );
  }
}

/// Dropdown card for picking a teacher/adviser — [value]/[onChanged] carry
/// the selected option's [TeacherOptionData.id], fed straight through to
/// [ViolationKioskScreen.onConfirm]'s `professorId`.
class _TeacherDropdownCard extends StatelessWidget {
  const _TeacherDropdownCard({
    required this.teachers,
    required this.value,
    required this.onChanged,
  });

  final List<TeacherOptionData> teachers;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return KioskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KioskFieldLabel('Teacher / Adviser'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            // Default row height (kMinInteractiveDimension, 48px) already
            // nearly matches 24px text + centering slack, so padding inside
            // the item was invisible — it just got squeezed into the same
            // ~48px box. Growing the row itself is what actually creates a
            // visible ~16px gap (8px top + 8px bottom slack) between items.
            itemHeight: 64,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: KioskColors.textSecondary,
            ),
            style: kioskPoppins(fontSize: 24, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              filled: true,
              fillColor: KioskColors.gradientTop,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: KioskColors.itemBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: KioskColors.itemBorder),
              ),
            ),
            hint: Text(
              'Select a teacher',
              style: kioskPoppins(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                color: KioskColors.textMuted,
              ),
            ),
            items: [
              for (final teacher in teachers)
                DropdownMenuItem(
                  value: teacher.id,
                  child: Text(
                    teacher.fullName,
                    style: kioskPoppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: KioskColors.textPrimary,
                    ),
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
