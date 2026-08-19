import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import '../../theme/discipline_officer_colors.dart';

// ---------------------------------------------------------------------------
// Left column — Violation Queue
// ---------------------------------------------------------------------------

/// Searchable/filterable list of pending violation slips. Structured to
/// match `professor_module`'s `ConductStudentListCard` exactly — same
/// header layout, search+filter row, and row treatment — so every dashboard
/// in this system reads as one consistent design system.
class ValidationQueueCard extends StatefulWidget {
  const ValidationQueueCard({
    super.key,
    required this.cases,
    required this.selectedCaseId,
    required this.onSelect,
    this.onViewArchived,
  });

  final List<DisciplineCaseModel> cases;
  final String? selectedCaseId;
  final ValueChanged<DisciplineCaseModel> onSelect;

  /// Opens a read-only list of archived ("deleted") reports still inside
  /// their retention window. Omitted (no button shown) when the host page
  /// has no backing archive source (e.g. demo/offline mode).
  final VoidCallback? onViewArchived;

  @override
  State<ValidationQueueCard> createState() => _ValidationQueueCardState();
}

class _ValidationQueueCardState extends State<ValidationQueueCard> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DisciplineCaseModel> get _filteredCases {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.cases;
    return widget.cases.where((c) {
      return c.studentName.toLowerCase().contains(query) ||
          c.studentNumber.toLowerCase().contains(query) ||
          c.violationType.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCases = _filteredCases;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DisciplineOfficerColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Violation Queue',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: DisciplineOfficerColors.rowText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pending slips: ${widget.cases.length} | Oldest first',
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 11 : 13,
                          fontWeight: FontWeight.w400,
                          color:
                              DisciplineOfficerColors.placeholderText(context),
                        ),
                      ),
                    ),
                    if (widget.onViewArchived != null)
                      InkWell(
                        onTap: widget.onViewArchived,
                        child: Text(
                          'View Archived',
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 11 : 13,
                            fontWeight: FontWeight.w600,
                            color: DisciplineOfficerColors.azureBlue,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 19, 25, 0),
            child: Row(
              children: [
                Expanded(
                  child: _QueueSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 10),
                _QueueFilterButton(onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: filteredCases.isEmpty
                ? const _QueueEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    itemCount: filteredCases.length,
                    itemBuilder: (context, index) {
                      final caseItem = filteredCases[index];
                      return _QueueRow(
                        caseItem: caseItem,
                        isSelected: caseItem.id == widget.selectedCaseId,
                        onTap: () => widget.onSelect(caseItem),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueSearchField extends StatelessWidget {
  const _QueueSearchField({required this.controller, required this.onChanged});

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
          color: DisciplineOfficerColors.rowText(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          hintStyle: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: DisciplineOfficerColors.placeholderText(context),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: DisciplineOfficerColors.placeholderText(context),
          ),
          filled: true,
          fillColor: DisciplineOfficerColors.background(context),
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

class _QueueFilterButton extends StatelessWidget {
  const _QueueFilterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DisciplineOfficerColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          width: 107,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: DisciplineOfficerColors.placeholderText(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w400,
                  color: DisciplineOfficerColors.placeholderText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueEmptyState extends StatelessWidget {
  const _QueueEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No pending validation slips',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: FontWeight.w500,
          color: DisciplineOfficerColors.mutedText(context),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.caseItem,
    required this.isSelected,
    required this.onTap,
  });

  final DisciplineCaseModel caseItem;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? DisciplineOfficerColors.selectedRow(context)
          : DisciplineOfficerColors.card(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: DisciplineOfficerColors.cardBorder(context))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                caseItem.studentName,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: DisciplineOfficerColors.rowText(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caseItem.programGradeSection,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: DisciplineOfficerColors.mutedText(context),
                ),
              ),
              Text(
                caseItem.studentNumber,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: DisciplineOfficerColors.mutedText(context),
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
// Right column — stat cards
// ---------------------------------------------------------------------------

class ViolationStatsRow extends StatelessWidget {
  const ViolationStatsRow({super.key, required this.metrics});

  final DisciplineSummaryMetricsModel metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final cards = [
          _StatCard(
            label: 'Pending Queue',
            value: '${metrics.pendingQueueCount}',
            icon: Icons.checklist_rounded,
          ),
          _StatCard(
            label: 'Escalated',
            value: '${metrics.escalatedCount}',
            icon: Icons.report_gmailerrorred_rounded,
          ),
          _StatCard(
            label: 'Processed Today',
            value: '${metrics.processedTodayCount}',
            icon: Icons.check_circle_outline_rounded,
          ),
          _StatCard(
            label: 'Avg. Response',
            value: _formatAvgResponseTime(metrics.avgResponseTimeMinutes),
            icon: Icons.trending_up_rounded,
          ),
        ];

        if (isNarrow) {
          return MobileMetricGrid(cards: cards);
        }

        return SizedBox(
          height: 124,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DisciplineOfficerColors.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: DisciplineOfficerColors.mutedText(context),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 30 : 32,
                      fontWeight: FontWeight.w600,
                      color: DisciplineOfficerColors.statValue(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon,
              size: 24, color: DisciplineOfficerColors.mutedText(context)),
        ],
      ),
    );
  }
}

String _formatAvgResponseTime(double minutes) {
  final totalSeconds = (minutes * 60).round();
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m}m ${s}s';
}

// ---------------------------------------------------------------------------
// Right column — Preview panel
// ---------------------------------------------------------------------------

class ViolationPreviewPanel extends StatelessWidget {
  const ViolationPreviewPanel({
    super.key,
    required this.selectedCase,
    required this.onValidate,
    required this.onModify,
    required this.onDelete,
    this.expandContent = true,
  });

  final DisciplineCaseModel? selectedCase;
  final VoidCallback onValidate;
  final VoidCallback onModify;
  final VoidCallback onDelete;

  /// True (desktop) when the caller gives this panel a bounded height to
  /// fill — the middle section and its Comments box use `Expanded` to eat
  /// whatever space is left. False (mobile) when there's no bounded height
  /// to fill because the page scrolls instead — the panel sizes itself to
  /// its own content, with the Comments box getting a fixed height instead
  /// of an `Expanded` that would need an ancestor to bound it.
  final bool expandContent;

  @override
  Widget build(BuildContext context) {
    final caseItem = selectedCase;
    final canAct = caseItem != null;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DisciplineOfficerColors.cardBorder(context)),
      ),
      // Column fills the panel's full given height (no ScrollView shrink-
      // wrap) so the Comments section's Expanded can eat the remaining
      // space instead of leaving a gap above the action buttons. On mobile
      // (expandContent: false) it sizes to its own content instead, since
      // there's no bounded height being handed down to fill.
      child: Column(
        mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preview',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: DisciplineOfficerColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caseItem == null
                          ? 'Select a slip from the violation queue'
                          : 'Submitted ${_timeAgoLabel(caseItem.incidentDateTime)}',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w400,
                        color: DisciplineOfficerColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              _SlaBadge(label: caseItem?.slaRemaining),
            ],
          ),
          const SizedBox(height: 16),
          _buildMiddleContent(context, caseItem),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  color: DisciplineOfficerColors.denyRed,
                  mutedColor: DisciplineOfficerColors.denyMuted,
                  onPressed: canAct ? onDelete : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Modify',
                  icon: Icons.edit_outlined,
                  color: DisciplineOfficerColors.modifyBlue,
                  mutedColor: DisciplineOfficerColors.modifyMuted,
                  onPressed: canAct ? onModify : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Validate',
                  icon: Icons.check_rounded,
                  color: DisciplineOfficerColors.validateGreen,
                  mutedColor: DisciplineOfficerColors.validateMuted,
                  onPressed: canAct ? onValidate : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleContent(
      BuildContext context, DisciplineCaseModel? caseItem) {
    if (caseItem == null) {
      return expandContent
          ? const Expanded(child: _PreviewEmptyState())
          : const SizedBox(height: 240, child: _PreviewEmptyState());
    }

    final content = Column(
      mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ViolationBanner(label: caseItem.violationType),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 560;
            final studentInfo = _InfoCard(
              icon: Icons.person_outline_rounded,
              title: 'Student Information',
              fields: [
                _InfoField(label: 'Name', value: caseItem.studentName),
                _InfoField(
                  label: 'Student number',
                  value: caseItem.studentNumber,
                ),
                _InfoField(
                  label: 'Year & Section',
                  value: caseItem.programGradeSection,
                ),
                _InfoField(
                  label: 'Previous violations',
                  value: caseItem.priorViolationsCount == 0
                      ? 'None'
                      : '${caseItem.priorViolationsCount} violation'
                          '${caseItem.priorViolationsCount == 1 ? '' : 's'}',
                ),
              ],
            );
            final violationDetails = _InfoCard(
              icon: Icons.menu_book_outlined,
              title: 'Violation Details',
              fields: [
                _InfoField(label: 'Submitted by', value: caseItem.submittedBy),
                _InfoField(label: 'Role', value: caseItem.submitterRole),
                _InfoField(
                  label: 'Date & Time',
                  value: _formatFullDateTime(caseItem.incidentDateTime),
                ),
              ],
            );

            if (stack) {
              return Column(
                children: [
                  studentInfo,
                  const SizedBox(height: 16),
                  violationDetails,
                ],
              );
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: studentInfo),
                  const SizedBox(width: 16),
                  Expanded(child: violationDetails),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        expandContent
            ? Expanded(child: _CommentsCard(text: caseItem.description))
            : SizedBox(
                height: 160, child: _CommentsCard(text: caseItem.description)),
      ],
    );

    return expandContent ? Expanded(child: content) : content;
  }
}

class _PreviewEmptyState extends StatelessWidget {
  const _PreviewEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: DisciplineOfficerColors.background(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.fact_check_outlined,
              size: 32,
              color: DisciplineOfficerColors.placeholderText(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No case selected',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: DisciplineOfficerColors.rowText(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a pending slip from the queue to review it',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 10 : 12,
              fontWeight: FontWeight.w400,
              color: DisciplineOfficerColors.mutedText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlaBadge extends StatelessWidget {
  const _SlaBadge({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.gray(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded,
              size: 14, color: DisciplineOfficerColors.rowText(context)),
          const SizedBox(width: 6),
          Text(
            'SLA Deadline ${label ?? '--:--'}',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 10 : 12,
              fontWeight: FontWeight.w400,
              color: DisciplineOfficerColors.rowText(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-visible banner naming the case's offense — e.g. "Minor - Improper
/// Uniform".
class _ViolationBanner extends StatelessWidget {
  const _ViolationBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.violationBannerBg(context),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: DisciplineOfficerColors.violationBannerBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined,
              size: 18, color: DisciplineOfficerColors.rowText(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: DisciplineOfficerColors.rowText(context),
              ),
            ),
          ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: DisciplineOfficerColors.cardBorderLight(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 16, color: DisciplineOfficerColors.rowText(context)),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: DisciplineOfficerColors.rowText(context),
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
            color: DisciplineOfficerColors.mutedText(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          field.value,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w500,
            color: DisciplineOfficerColors.rowText(context),
          ),
        ),
      ],
    );
  }
}

/// The comment/description box. Always wrapped in `Expanded` by the caller
/// so it dynamically stretches to fill whatever vertical space is left
/// above the action buttons — no fixed height, no bottom gap.
class _CommentsCard extends StatelessWidget {
  const _CommentsCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: DisciplineOfficerColors.cardBorderLight(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 16, color: DisciplineOfficerColors.rowText(context)),
              const SizedBox(width: 8),
              Text(
                'Comments',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: DisciplineOfficerColors.rowText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: DisciplineOfficerColors.background(context),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(18),
              child: TextField(
                controller: TextEditingController(text: text),
                readOnly: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: DisciplineOfficerColors.rowText(context),
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.mutedColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color mutedColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: enabled ? color : mutedColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
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

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatFullDateTime(DateTime dateTime) {
  final month = _months[dateTime.month - 1];
  final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$month ${dateTime.day}, ${dateTime.year}, $hour12:$minute $period';
}

String _timeAgoLabel(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}
