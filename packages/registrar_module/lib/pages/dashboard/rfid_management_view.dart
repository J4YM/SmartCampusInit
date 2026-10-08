import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'registrar_dashboard_page.dart';

// ---------------------------------------------------------------------------
// RFID Management tab — "Student Without RFID" table with bulk selection,
// "View Logs", and "Submit & Notify".
// ---------------------------------------------------------------------------

class RfidManagementView extends StatefulWidget {
  const RfidManagementView({
    super.key,
    required this.students,
    this.onSubmitNotify,
    this.onViewLogs,
  });

  final List<RegistrarStudentModel> students;

  /// Called with the ids of every checked student when "Submit & Notify" is
  /// tapped. Falls back to no-op when omitted (demo behavior).
  final ValueChanged<List<String>>? onSubmitNotify;

  /// Falls back to no-op when omitted (demo behavior — no log history to
  /// show yet).
  final VoidCallback? onViewLogs;

  @override
  State<RfidManagementView> createState() => _RfidManagementViewState();
}

class _RfidManagementViewState extends State<RfidManagementView> {
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;
  final Set<String> _selectedIds = {};
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The students the search leaves visible — what the table, its
  /// pagination and the select-all checkbox all work on.
  List<RegistrarStudentModel> get _visibleStudents => [
        for (final s in widget.students)
          if (matchesSearchQuery(_query, [s.name, s.studentId, s.section])) s,
      ];

  bool get _allSelected {
    final visible = _visibleStudents;
    return visible.isNotEmpty &&
        visible.every((s) => _selectedIds.contains(s.id));
  }

  void _toggleSelectAll() {
    final visible = _visibleStudents;
    setState(() {
      if (_allSelected) {
        _selectedIds.removeAll(visible.map((s) => s.id));
      } else {
        _selectedIds.addAll(visible.map((s) => s.id));
      }
    });
  }

  /// Ticked students the search currently shows. A tick hidden by the search
  /// is remembered (it comes back when the search is cleared) but never sent:
  /// "Submit & Notify" only reaches students the registrar can see ticked.
  List<String> get _selectedVisibleIds => [
        for (final s in _visibleStudents)
          if (_selectedIds.contains(s.id)) s.id,
      ];

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final students = _visibleStudents;
    final totalPages =
        students.isEmpty ? 1 : (students.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  'Student Without RFID',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SecondaryPillButton(
                      label: 'View Logs',
                      icon: Icons.history_rounded,
                      onTap: widget.onViewLogs ?? () {},
                    ),
                    _PillActionButton(
                      label: 'Submit & Notify',
                      background: RegistrarColors.azureBlue,
                      foreground: Colors.white,
                      icon: Icons.mark_email_read_outlined,
                      onTap: _selectedVisibleIds.isEmpty
                          ? null
                          : () => widget.onSubmitNotify
                              ?.call(_selectedVisibleIds),
                    ),
                  ],
                );
                final search = SearchField(
                  controller: _searchController,
                  hintText: 'Search students',
                  onChanged: _onSearchChanged,
                );

                // Wide: title, search and both buttons share one line.
                // Narrower: the search takes its own line under the
                // title/buttons.
                if (!context.isMobileWidth && constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      title,
                      const SizedBox(width: 16),
                      Expanded(
                        child: MaxWidthAligned(
                          alignment: Alignment.centerRight,
                          child: search,
                        ),
                      ),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [title, actions],
                    ),
                    const SizedBox(height: 12),
                    MaxWidthAligned(child: search),
                  ],
                );
              },
            ),
          ),
          DashboardTableSection(
            columns: _rfidNotifyColumns,
            headerLeading: _RowCheckbox(
              value: _allSelected,
              onChanged: (_) => _toggleSelectAll(),
            ),
            // The checkbox (28px) and its gap.
            leadingWidth: 28 + DashboardTableMetrics.columnGap,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pageStudents.isEmpty)
                  DashboardTableEmptyState(
                    icon: Icons.contactless_outlined,
                    message: widget.students.isEmpty
                        ? 'Every enrolled student already has an RFID card'
                        : 'No students match your search',
                  )
                else
                  for (var i = 0; i < pageStudents.length; i++)
                    _RfidRow(
                      student: pageStudents[i],
                      showDivider: i < pageStudents.length - 1,
                      isSelected: _selectedIds.contains(pageStudents[i].id),
                      onChanged: (checked) => setState(() {
                        checked == true
                            ? _selectedIds.add(pageStudents[i].id)
                            : _selectedIds.remove(pageStudents[i].id);
                      }),
                    ),
              ],
            ),
          ),
          if (students.isNotEmpty)
            DashboardTableFooter(
              child: CardPaginationFooter(
                currentPage: currentPage,
                totalPages: totalPages,
                totalCount: students.length,
                textColor: RegistrarColors.mutedText(context),
                accentColor: RegistrarColors.azureBlue,
                mutedBackground: RegistrarColors.background(context),
                onPrevious: () =>
                    setState(() => _currentPage = currentPage - 1),
                onNext: () => setState(() => _currentPage = currentPage + 1),
              ),
            ),
        ],
      ),
    );
  }
}

const _rfidNotifyColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student Name', flex: 2, minWidth: 220),
  DashboardTableColumn('Student ID', flex: 1, minWidth: 120),
  DashboardTableColumn('Grade & Section', flex: 1, minWidth: 150),
  DashboardTableColumn('Status', flex: 1, compact: true, minWidth: 110),
];

/// The select checkbox in front of the header and each row — the same
/// width in both so the columns after it stay aligned.
class _RowCheckbox extends StatelessWidget {
  const _RowCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: DashboardTableMetrics.columnGap),
      child: SizedBox(
        width: 28,
        child: Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: subNavActiveColor(context, RegistrarColors.azureBlue),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _RfidRow extends StatelessWidget {
  const _RfidRow({
    required this.student,
    required this.showDivider,
    required this.isSelected,
    required this.onChanged,
  });

  final RegistrarStudentModel student;
  final bool showDivider;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _rfidNotifyColumns,
      showDivider: showDivider,
      selected: isSelected,
      onTap: () => onChanged(!isSelected),
      leading: _RowCheckbox(value: isSelected, onChanged: onChanged),
      cells: [
        Text(
          student.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTablePrimaryStyle(context),
        ),
        Text(
          student.studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableIdStyle(context),
        ),
        Text(
          student.section,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0x33CD4855),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'No RFID',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: RegistrarColors.dangerRed,
            ),
          ),
        ),
      ],
    );
  }
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: disabled ? foreground.withOpacity(0.6) : foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
