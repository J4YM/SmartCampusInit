import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/kiosk_colors.dart';

class ViolationItemData {
  const ViolationItemData({required this.title, required this.code});

  final String title;
  final String code;
}

class ViolationCategoryData {
  const ViolationCategoryData({
    required this.badgeLabel,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.items,
  });

  final String badgeLabel;
  final Color badgeBackground;
  final Color badgeForeground;
  final List<ViolationItemData> items;
}

class ViolationKioskScreen extends StatefulWidget {
  const ViolationKioskScreen({
    super.key,
    this.studentName = '',
    this.studentId = '',
  });

  /// Full name shown in the student card; when empty, a muted placeholder is shown.
  final String studentName;

  /// Student number/id shown after "Student No: "; when empty, a muted placeholder is shown.
  final String studentId;

  @override
  State<ViolationKioskScreen> createState() => _ViolationKioskScreenState();
}

class _ViolationKioskScreenState extends State<ViolationKioskScreen> {
  final Set<String> _selectedCodes = {};

  static const List<ViolationCategoryData> _categories = [
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

  TextStyle _poppins({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = KioskColors.textPrimary,
    double height = 1.35,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedCodes.length;

    return Scaffold(
      backgroundColor: KioskColors.gradientTop,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KioskHeader(),
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    KioskColors.gradientTop,
                    KioskColors.gradientBottom,
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StudentInfoCard(
                          style: _poppins,
                          studentName: widget.studentName,
                          studentId: widget.studentId,
                        ),
                        const SizedBox(height: 20),
                        _InstructionAlert(style: _poppins),
                        const SizedBox(height: 20),
                        for (final cat in _categories) ...[
                          _ViolationCategoryCard(
                            category: cat,
                            selectedCodes: _selectedCodes,
                            onToggle: _toggleCode,
                            poppins: _poppins,
                          ),
                          const SizedBox(height: 20),
                        ],
                        _FooterActionBar(
                          selectedCount: selectedCount,
                          onConfirm: selectedCount == 0
                              ? null
                              : () {
                                  // Hook for slip generation
                                },
                          poppins: _poppins,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KioskHeader extends StatelessWidget {
  const _KioskHeader();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KioskColors.headerNavy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Column(
            children: [
              Text(
                'STI College Baliuag',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Virtual Admission Kiosk',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.95),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _PoppinsStyle = TextStyle Function({
  double fontSize,
  FontWeight fontWeight,
  Color color,
  double height,
});

class _StudentInfoCard extends StatelessWidget {
  const _StudentInfoCard({
    required this.style,
    required this.studentName,
    required this.studentId,
  });

  final _PoppinsStyle style;
  final String studentName;
  final String studentId;

  static const String _emptyPlaceholder = '—';

  @override
  Widget build(BuildContext context) {
    final name = studentName.trim();
    final id = studentId.trim();
    final nameDisplay = name.isNotEmpty ? name : _emptyPlaceholder;
    final idDisplay = id.isNotEmpty ? id : _emptyPlaceholder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: KioskColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameDisplay,
                  style: style(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: name.isNotEmpty
                        ? KioskColors.textPrimary
                        : KioskColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: style(
                      fontSize: 13,
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
          TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: KioskColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            label: Text(
              'Back',
              style: style(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KioskColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionAlert extends StatelessWidget {
  const _InstructionAlert({required this.style});

  final _PoppinsStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KioskColors.alertBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KioskColors.alertBorder.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: KioskColors.alertBorder,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please select your violation(s)',
                  style: style(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KioskColors.alertTitle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select all violations that apply to you. You must acknowledge '
                  'your violations to proceed.',
                  style: style(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: KioskColors.alertBody,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViolationCategoryCard extends StatelessWidget {
  const _ViolationCategoryCard({
    required this.category,
    required this.selectedCodes,
    required this.onToggle,
    required this.poppins,
  });

  final ViolationCategoryData category;
  final Set<String> selectedCodes;
  final void Function(String code) onToggle;
  final _PoppinsStyle poppins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: KioskColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: category.badgeBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              category.badgeLabel,
              style: poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: category.badgeForeground,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < category.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ViolationRow(
              item: category.items[i],
              selected: selectedCodes.contains(category.items[i].code),
              onTap: () => onToggle(category.items[i].code),
              poppins: poppins,
            ),
          ],
        ],
      ),
    );
  }
}

class _ViolationRow extends StatelessWidget {
  const _ViolationRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.poppins,
  });

  final ViolationItemData item;
  final bool selected;
  final VoidCallback onTap;
  final _PoppinsStyle poppins;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: KioskColors.cardWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KioskColors.itemBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _KioskCheckbox(checked: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KioskColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KioskCheckbox extends StatelessWidget {
  const _KioskCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? KioskColors.headerNavy : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? KioskColors.headerNavy : KioskColors.checkboxBorder,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _FooterActionBar extends StatelessWidget {
  const _FooterActionBar({
    required this.selectedCount,
    required this.onConfirm,
    required this.poppins,
  });

  final int selectedCount;
  final VoidCallback? onConfirm;
  final _PoppinsStyle poppins;

  @override
  Widget build(BuildContext context) {
    final enabled = onConfirm != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: KioskColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final button = FilledButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: Text(
              'Confirm & Generate Slip',
              style: poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: enabled
                  ? KioskColors.enabledButton
                  : KioskColors.disabledButton,
              foregroundColor: Colors.white,
              disabledBackgroundColor: KioskColors.disabledButton,
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          );

          final leftColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$selectedCount violation(s) selected',
                style: poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KioskColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Review your selection and confirm to generate admission slip',
                style: poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: KioskColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftColumn,
                const SizedBox(height: 16),
                button,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: leftColumn),
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    );
  }
}
