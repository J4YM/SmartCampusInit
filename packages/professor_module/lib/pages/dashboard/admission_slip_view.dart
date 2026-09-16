import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/professor_colors.dart';

// ---------------------------------------------------------------------------
// Data models — mock-data only for now (see admission_slip_mock_data.dart).
// Shaped so a later Supabase-backed pass (`admission_slips` +
// `student_violations`) can populate these directly.
// ---------------------------------------------------------------------------

enum AdmissionSlipStatus { pending, approved, declined }

class AdmissionSlipViolationEntry {
  const AdmissionSlipViolationEntry({
    required this.offenseLabel,
    required this.category,
  });

  final String offenseLabel;
  final String category;
}

class AdmissionSlipModel {
  const AdmissionSlipModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.submittedAt,
    required this.status,
    required this.violations,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final DateTime submittedAt;
  final AdmissionSlipStatus status;
  final List<AdmissionSlipViolationEntry> violations;

  AdmissionSlipModel copyWith({AdmissionSlipStatus? status}) {
    return AdmissionSlipModel(
      id: id,
      studentName: studentName,
      studentNumber: studentNumber,
      section: section,
      submittedAt: submittedAt,
      status: status ?? this.status,
      violations: violations,
    );
  }
}

String _formatDate(DateTime dateTime) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final month = months[dateTime.month - 1];
  final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$month ${dateTime.day}, ${dateTime.year} | $hour12:$minute $period';
}

// ---------------------------------------------------------------------------
// Left column — Admission Slip list
// ---------------------------------------------------------------------------

class AdmissionSlipListCard extends StatefulWidget {
  const AdmissionSlipListCard({
    super.key,
    required this.slips,
    required this.totalSlipCount,
    required this.selectedSlipId,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSelect,
    required this.availableSections,
    required this.sectionFilter,
    required this.onSectionFilterChanged,
  });

  final List<AdmissionSlipModel> slips;
  final int totalSlipCount;
  final String? selectedSlipId;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AdmissionSlipModel> onSelect;

  final List<String> availableSections;
  final String? sectionFilter;
  final ValueChanged<String?> onSectionFilterChanged;

  @override
  State<AdmissionSlipListCard> createState() => _AdmissionSlipListCardState();
}

class _AdmissionSlipListCardState extends State<AdmissionSlipListCard> {
  int get _pageSize => context.cardPageSize;

  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final slips = widget.slips;
    final totalPages = slips.isEmpty ? 1 : (slips.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageSlips =
        slips.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = slips.isEmpty
            ? const _SlipListEmptyState()
            : ListView.separated(
                shrinkWrap: !bounded,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                itemCount: pageSlips.length,
                separatorBuilder: (context, index) => const SizedBox(height: 0),
                itemBuilder: (context, index) {
                  final slip = pageSlips[index];
                  return _SlipRow(
                    slip: slip,
                    isSelected: slip.id == widget.selectedSlipId,
                    onTap: () => widget.onSelect(slip),
                  );
                },
              );

        return BentoCard(
          backgroundColor: ProfessorColors.card(context),
          borderColor: ProfessorColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admission Slips',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: ProfessorColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total slips: ${widget.totalSlipCount}',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w400,
                        color: ProfessorColors.placeholderText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 19, 25, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _SlipSearchField(
                        controller: widget.searchController,
                        onChanged: (value) {
                          setState(() => _currentPage = 1);
                          widget.onSearchChanged(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilterMenuButton(
                      backgroundColor: ProfessorColors.background(context),
                      menuColor: ProfessorColors.card(context),
                      borderColor: ProfessorColors.cardBorder(context),
                      iconColor: ProfessorColors.placeholderText(context),
                      textColor: ProfessorColors.rowText(context),
                      mutedTextColor: ProfessorColors.mutedText(context),
                      accentColor: ProfessorColors.azureBlue,
                      sections: [
                        FilterMenuSection(
                          title: 'Section',
                          options: [
                            for (final section in widget.availableSections)
                              FilterMenuOption(label: section, value: section),
                          ],
                          selectedValue: widget.sectionFilter,
                          onChanged: (value) {
                            setState(() => _currentPage = 1);
                            widget.onSectionFilterChanged(value);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (slips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: slips.length,
                    textColor: ProfessorColors.placeholderText(context),
                    accentColor: ProfessorColors.azureBlue,
                    mutedBackground: ProfessorColors.background(context),
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () =>
                        setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SlipSearchField extends StatelessWidget {
  const _SlipSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          color: ProfessorColors.rowText(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          hintStyle: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: ProfessorColors.placeholderText(context),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: ProfessorColors.placeholderText(context),
          ),
          filled: true,
          fillColor: ProfessorColors.background(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SlipListEmptyState extends StatelessWidget {
  const _SlipListEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No admission slips found',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: FontWeight.w500,
          color: ProfessorColors.mutedText(context),
        ),
      ),
    );
  }
}

class _SlipRow extends StatelessWidget {
  const _SlipRow({
    required this.slip,
    required this.isSelected,
    required this.onTap,
  });

  final AdmissionSlipModel slip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? ProfessorColors.selectedRow(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ProfessorColors.cardBorder(context)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slip.studentName,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: ProfessorColors.rowText(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${slip.section} · ${slip.studentNumber}',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.mutedText(context),
                ),
              ),
              Text(
                _formatDate(slip.submittedAt),
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Admission Slip detail panel
// ---------------------------------------------------------------------------

class AdmissionSlipDetailCard extends StatelessWidget {
  const AdmissionSlipDetailCard({
    super.key,
    required this.selectedSlip,
    required this.onApprove,
    required this.onDecline,
  });

  final AdmissionSlipModel? selectedSlip;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final slip = selectedSlip;
    final title = Text(
      'Admission Slip',
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 16 : 18,
        fontWeight: FontWeight.w600,
        color: ProfessorColors.rowText(context),
      ),
    );

    final middle = slip == null
        ? _NoSlipSelectedState(isMobile: context.isMobileWidth)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 640;
                  final studentInfo = _InfoCard(
                    icon: Icons.person_outline_rounded,
                    title: 'Student Information',
                    fields: [
                      _InfoField(label: 'Name', value: slip.studentName),
                      _InfoField(
                        label: 'Student number',
                        value: slip.studentNumber,
                      ),
                      _InfoField(label: 'Year & Section', value: slip.section),
                      _InfoField(
                        label: 'Submitted',
                        value: _formatDate(slip.submittedAt),
                      ),
                    ],
                  );
                  final violationsCard = _ViolationsCard(
                    violations: slip.violations,
                  );

                  if (stack) {
                    return Column(
                      children: [
                        studentInfo,
                        const SizedBox(height: 16),
                        violationsCard,
                      ],
                    );
                  }

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: studentInfo),
                        const SizedBox(width: 19),
                        Expanded(child: violationsCard),
                      ],
                    ),
                  );
                },
              ),
            ],
          );

    final actions = Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Decline',
            color: ProfessorColors.dangerRed,
            icon: Icons.close_rounded,
            onTap: onDecline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Approve',
            color: ProfessorColors.successGreen,
            icon: Icons.check_rounded,
            onTap: onApprove,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        return BentoCard(
          backgroundColor: ProfessorColors.card(context),
          borderColor: ProfessorColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 18),
              bounded
                  ? Expanded(child: SingleChildScrollView(child: middle))
                  : middle,
              const SizedBox(height: 16),
              actions,
            ],
          ),
        );
      },
    );
  }
}

class _NoSlipSelectedState extends StatelessWidget {
  const _NoSlipSelectedState({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'Select an admission slip to view its details',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: isMobile ? 12 : 14,
            fontWeight: FontWeight.w500,
            color: ProfessorColors.mutedText(context),
          ),
        ),
      ),
    );
  }
}

class _ViolationsCard extends StatelessWidget {
  const _ViolationsCard({required this.violations});

  final List<AdmissionSlipViolationEntry> violations;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: ProfessorColors.card(context),
      borderColor: ProfessorColors.cardBorderLight(context),
      borderRadius: 14,
      elevated: false,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 16,
                color: ProfessorColors.rowText(context),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Violations Filed',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.rowText(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < violations.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: ProfessorColors.azureBlue,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        violations[i].offenseLabel,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 11 : 13,
                          fontWeight: FontWeight.w500,
                          color: ProfessorColors.rowText(context),
                        ),
                      ),
                      Text(
                        violations[i].category,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 9 : 11,
                          fontWeight: FontWeight.w400,
                          color: ProfessorColors.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoField {
  const _InfoField({required this.label, required this.value});

  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.fields});

  final IconData icon;
  final String title;
  final List<_InfoField> fields;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: ProfessorColors.card(context),
      borderColor: ProfessorColors.cardBorderLight(context),
      borderRadius: 14,
      elevated: false,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: ProfessorColors.rowText(context)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.rowText(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Wrap(
            runSpacing: 26,
            children: [
              for (var i = 0; i < fields.length; i += 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _InfoFieldText(field: fields[i])),
                    if (i + 1 < fields.length)
                      Expanded(child: _InfoFieldText(field: fields[i + 1])),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoFieldText extends StatelessWidget {
  const _InfoFieldText({required this.field});

  final _InfoField field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.label,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 9 : 11,
            fontWeight: FontWeight.w400,
            color: ProfessorColors.mutedText(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          field.value,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w500,
            color: ProfessorColors.rowText(context),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? color : color.withOpacity(0.4),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 33,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
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
