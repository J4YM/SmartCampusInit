import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/good_moral_models.dart';
import '../../theme/discipline_officer_colors.dart';

// ---------------------------------------------------------------------------
// Pill sub-tab bar (Requests / Student List)
// ---------------------------------------------------------------------------

/// Capsule-shaped toggle above the queue card — distinct from the flat
/// underline tabs used by the top-level `DashboardHeaderNavBar`.
class GoodMoralSubTabBar extends StatelessWidget {
  const GoodMoralSubTabBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  final GoodMoralSubTab activeTab;
  final ValueChanged<GoodMoralSubTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: DisciplineOfficerColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SubTabPill(
              label: 'Requests',
              icon: Icons.inbox_outlined,
              isActive: activeTab == GoodMoralSubTab.requests,
              onTap: () => onTabSelected(GoodMoralSubTab.requests),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SubTabPill(
              label: 'Student List',
              icon: Icons.people_outline,
              isActive: activeTab == GoodMoralSubTab.studentsList,
              onTap: () => onTabSelected(GoodMoralSubTab.studentsList),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabPill extends StatelessWidget {
  const _SubTabPill({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        isActive ? Colors.white : DisciplineOfficerColors.azureBlue;
    return Material(
      color: isActive ? DisciplineOfficerColors.azureBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w600,
                  color: color,
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
// Left column — Requests / Student List queue card
// ---------------------------------------------------------------------------

/// One row's worth of display data — the caller reduces either a
/// `GoodMoralRequestModel` or a `StudentDirectoryEntryModel` down to this
/// common shape, since both sub-tabs render identical Name/Section/Number
/// rows (matching every other dashboard's queue list in this system).
class GoodMoralQueueRowData {
  const GoodMoralQueueRowData({
    required this.id,
    required this.name,
    required this.section,
    required this.number,
    this.groupLabel,
  });

  final String id;
  final String name;
  final String section;
  final String number;

  /// e.g. "BS Information Technology — Year 3" — when non-null, the queue
  /// list renders a header above the first row of each run of consecutive
  /// rows sharing the same label (see [GoodMoralQueueCard]). Left null for
  /// the Requests tab, which isn't grouped.
  final String? groupLabel;
}

class GoodMoralQueueCard extends StatefulWidget {
  const GoodMoralQueueCard({
    super.key,
    required this.title,
    required this.totalCountLabel,
    required this.rows,
    required this.selectedId,
    required this.onSelect,
    this.isLoading = false,
    this.footer,
  });

  final String title;
  final String totalCountLabel;
  final List<GoodMoralQueueRowData> rows;
  final String? selectedId;
  final ValueChanged<GoodMoralQueueRowData> onSelect;

  /// Shows a skeleton list instead of an empty state while [rows] is still
  /// loading its first page from the backend.
  final bool isLoading;

  /// Optional pagination controls rendered below the list.
  final Widget? footer;

  @override
  State<GoodMoralQueueCard> createState() => _GoodMoralQueueCardState();
}

class _GoodMoralQueueCardState extends State<GoodMoralQueueCard> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GoodMoralQueueRowData> get _filteredRows {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.rows;
    return widget.rows.where((r) {
      return r.name.toLowerCase().contains(query) ||
          r.section.toLowerCase().contains(query) ||
          r.number.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;

    // A caller-supplied footer means the caller already paginates `rows`
    // server-side (the Student List sub-tab) — only paginate client-side
    // here when nothing else is already limiting the row count (the
    // Requests sub-tab, fetched in full).
    final usesLocalPagination = widget.footer == null;
    final totalPages = !usesLocalPagination || rows.isEmpty
        ? 1
        : (rows.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageRows = usesLocalPagination
        ? rows.skip((currentPage - 1) * _pageSize).take(_pageSize).toList()
        : rows;

    // Header/search stay fixed; only the list scrolls — as a bounded,
    // real-scrolling Expanded when an ancestor gives this card a fixed
    // height to match its Preview panel sibling (the desktop master-detail
    // Row), or as a Flexible that hugs up to whatever's available when it
    // doesn't (mobile/stacked, where the page itself scrolls instead).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = widget.isLoading && widget.rows.isEmpty
            ? const _QueueSkeletonList()
            : rows.isEmpty
                ? const _QueueEmptyState()
                : ListView.builder(
                    shrinkWrap: !bounded,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    itemCount: pageRows.length,
                    itemBuilder: (context, index) {
                      final row = pageRows[index];
                      final previousRow =
                          index == 0 ? null : pageRows[index - 1];
                      final showHeader = row.groupLabel != null &&
                          row.groupLabel != previousRow?.groupLabel;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader)
                            _QueueGroupHeader(label: row.groupLabel!),
                          _QueueRow(
                            row: row,
                            isSelected: row.id == widget.selectedId,
                            onTap: () => widget.onSelect(row),
                          ),
                        ],
                      );
                    },
                  );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: DisciplineOfficerColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: DisciplineOfficerColors.cardBorder(context)),
          ),
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
                      widget.title,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: DisciplineOfficerColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.totalCountLabel,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w400,
                        color: DisciplineOfficerColors.placeholderText(context),
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
                      child: _QueueSearchField(
                        controller: _searchController,
                        onChanged: (value) => setState(() {
                          _searchQuery = value;
                          _currentPage = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _QueueFilterButton(onTap: () {}),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (widget.footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: widget.footer,
                )
              else if (usesLocalPagination && rows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: rows.length,
                    textColor: DisciplineOfficerColors.placeholderText(context),
                    accentColor: DisciplineOfficerColors.azureBlue,
                    mutedBackground: DisciplineOfficerColors.background(context),
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
        'No records found',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: FontWeight.w500,
          color: DisciplineOfficerColors.mutedText(context),
        ),
      ),
    );
  }
}

class _QueueSkeletonList extends StatefulWidget {
  const _QueueSkeletonList();

  @override
  State<_QueueSkeletonList> createState() => _QueueSkeletonListState();
}

class _QueueSkeletonListState extends State<_QueueSkeletonList>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final _opacity = Tween<double>(begin: 0.4, end: 0.9).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          itemCount: 6,
          itemBuilder: (context, index) => _skeletonRow(_opacity.value),
        );
      },
    );
  }

  Widget _skeletonRow(double opacity) {
    Widget bar(double width, double height) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color:
              DisciplineOfficerColors.cardBorder(context).withOpacity(opacity),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: DisciplineOfficerColors.cardBorder(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(140, 12),
          const SizedBox(height: 8),
          bar(90, 10),
          const SizedBox(height: 4),
          bar(110, 10),
        ],
      ),
    );
  }
}

/// Sticky-styled (but non-sticky — just visually anchored) label shown
/// above the first row of each program/year-level group in the Student
/// List tab. See [GoodMoralQueueRowData.groupLabel].
class _QueueGroupHeader extends StatelessWidget {
  const _QueueGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 10 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: DisciplineOfficerColors.placeholderText(context),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.row,
    required this.isSelected,
    required this.onTap,
  });

  final GoodMoralQueueRowData row;
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
                row.name,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: DisciplineOfficerColors.rowText(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                row.section,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: DisciplineOfficerColors.mutedText(context),
                ),
              ),
              Text(
                row.number,
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
// Right column — Preview panel
// ---------------------------------------------------------------------------

class GoodMoralPreviewPanel extends StatelessWidget {
  const GoodMoralPreviewPanel({
    super.key,
    required this.selected,
    required this.onGenerateCertificate,
  });

  final GoodMoralSelectedStudent? selected;
  final VoidCallback onGenerateCertificate;

  @override
  Widget build(BuildContext context) {
    final canGenerate = selected != null;

    final infoCards = selected == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ClearanceStatusBanner(
                hasActiveViolation: selected!.hasActiveViolation,
              ),
              const SizedBox(height: 16),
              _InfoCard(
                icon: Icons.person_outline_rounded,
                title: 'Student Information',
                fields: [
                  _InfoField(label: 'Name', value: selected!.studentName),
                  _InfoField(
                    label: 'Student number',
                    value: selected!.studentNumber,
                  ),
                  _InfoField(
                    label: 'Year & Section',
                    value: selected!.programGradeSection,
                  ),
                  if (selected!.previousViolationsCount != null)
                    _InfoField(
                      label: 'Previous violations',
                      value: selected!.previousViolationsCount == 0
                          ? 'None'
                          : '${selected!.previousViolationsCount} violations',
                    ),
                ],
              ),
              if (selected!.documentType != null) ...[
                const SizedBox(height: 16),
                _InfoCard(
                  icon: Icons.menu_book_outlined,
                  title: 'Request Details',
                  fields: [
                    _InfoField(
                      label: 'Document Type',
                      value: selected!.documentType!,
                    ),
                    _InfoField(
                      label: 'Purpose',
                      value: selected!.purpose ?? '—',
                    ),
                    _InfoField(
                      label: 'Requested by',
                      value: selected!.requestedBy ?? '—',
                    ),
                    _InfoField(
                      label: 'Date & Time',
                      value: selected!.requestDateTime == null
                          ? '—'
                          : _formatFullDateTime(selected!.requestDateTime!),
                    ),
                  ],
                ),
              ],
            ],
          );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
          'Select a student to view their information',
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w400,
            color: DisciplineOfficerColors.placeholderText(context),
          ),
        ),
      ],
    );
    final middle =
        infoCards ?? const SizedBox(height: 240, child: _PreviewEmptyState());
    final actionButton = Center(
      // Caps at 294px on a wide panel but shrinks to fit a narrow
      // one instead of forcing a fixed 294 + 28*2 padding = 350px
      // minimum panel width, which overflowed the card on mobile.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 294),
        child: SizedBox(
          width: double.infinity,
          child: _ActionButton(
            label: 'Generate & Print',
            icon: Icons.edit_outlined,
            onPressed: canGenerate ? onGenerateCertificate : null,
          ),
        ),
      ),
    );

    // Header and the action button stay fixed; when an ancestor gives this
    // panel a bounded height to match its queue sibling (the desktop
    // master-detail Row), the middle content scrolls internally within
    // whatever's left instead of overflowing past a fixed action button.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        return Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          decoration: BoxDecoration(
            color: DisciplineOfficerColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: DisciplineOfficerColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 16),
              bounded
                  ? Expanded(child: SingleChildScrollView(child: middle))
                  : middle,
              const SizedBox(height: 16),
              actionButton,
            ],
          ),
        );
      },
    );
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
            'No student selected',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: DisciplineOfficerColors.rowText(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a request or student to review it',
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

/// Reflects whether the student has an active (`Pending`/
/// `Under_Investigation`, non-archived) violation — a resolved or archived
/// violation doesn't count against clearance. See
/// `DisciplineRepository.fetchActiveViolationStudentIds`.
class _ClearanceStatusBanner extends StatelessWidget {
  const _ClearanceStatusBanner({required this.hasActiveViolation});

  final bool hasActiveViolation;

  @override
  Widget build(BuildContext context) {
    final bg = hasActiveViolation
        ? DisciplineOfficerColors.violationBannerBg(context)
        : DisciplineOfficerColors.infoBannerBg(context);
    final border = hasActiveViolation
        ? DisciplineOfficerColors.violationBannerBorder
        : DisciplineOfficerColors.infoBannerBorder;
    final icon = hasActiveViolation
        ? Icons.error_outline_rounded
        : Icons.info_outline_rounded;
    final label = hasActiveViolation
        ? 'Clearance Status: Not Clear — Pending Violation'
        : 'Clearance Status: Clear';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: DisciplineOfficerColors.rowText(context)),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: enabled
          ? DisciplineOfficerColors.azureBlue
          : DisciplineOfficerColors.modifyMuted,
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
  return '$month ${dateTime.day}, ${dateTime.year} | $hour12:$minute $period';
}
