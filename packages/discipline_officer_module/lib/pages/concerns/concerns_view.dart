import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../../models/concern_report_model.dart';
import '../../theme/discipline_officer_colors.dart';

/// Width of the table's far-right action column.
const double _kActionColumnWidth = 44;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Concern', flex: 4, minWidth: 190),
  DashboardTableColumn('About', flex: 3, minWidth: 170),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Priority', flex: 2, minWidth: 100),
  DashboardTableColumn('Status', flex: 2, minWidth: 120),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// The Discipline Officer's "Concerns" tab: support requests students filed
/// from their own dashboard, for themselves or for a classmate. Urgent and
/// still-open ones come first. A row opens the full concern, where the
/// officer sets the status and leaves a note the referrer can read; the icon
/// ending an open row endorses the student to the Guidance Associate.
class ConcernsView extends StatefulWidget {
  const ConcernsView({
    super.key,
    required this.concerns,
    this.onUpdate,
    this.onEndorse,
    this.endorsedConcernIds = const {},
  });

  final List<ConcernReportModel> concerns;

  /// Saves a status change / note. Null makes the tab read-only (demo).
  final Future<void> Function(
    ConcernReportModel concern, {
    required String status,
    String? note,
  })? onUpdate;

  /// Starts an endorsement for the concern's student. Null hides the action.
  final Future<void> Function(ConcernReportModel concern)? onEndorse;

  /// Concerns that already have an endorsement: they show "Endorsed" instead
  /// of the action.
  final Set<String> endorsedConcernIds;

  @override
  State<ConcernsView> createState() => _ConcernsViewState();
}

class _ConcernsViewState extends State<ConcernsView> {
  final _searchController = TextEditingController();
  String _query = '';

  /// `Pending`, `In_Progress` or `Closed`; null = every concern.
  String? _statusFilter;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Open before closed, urgent before routine, then newest first.
  List<ConcernReportModel> get _ordered {
    final list = [...widget.concerns];
    list.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<ConcernReportModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return _ordered.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.studentName.toLowerCase().contains(q) ||
          r.studentNumber.toLowerCase().contains(q) ||
          (r.aboutStudentName ?? '').toLowerCase().contains(q) ||
          r.concernLabel.toLowerCase().contains(q) ||
          r.details.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _open(ConcernReportModel r) async {
    final result = await showAppPopup<({String status, String note})>(
      context: context,
      builder: (_) =>
          _ConcernDialog(concern: r, canEdit: widget.onUpdate != null),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onUpdate!(r, status: result.status, note: result.note);
      messenger.showSnackBar(const SnackBar(content: Text('Concern updated.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not update the concern: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageSize = context.cardPageSize;
    final totalPages = filtered.isEmpty ? 1 : (filtered.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageItems =
        filtered.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final total = widget.concerns.length;
    final waiting = widget.concerns.where((r) => r.status == 'Pending').length;
    final urgent =
        widget.concerns.where((r) => r.isOpen && r.isUrgent).length;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _ConcernRow(
          key: ValueKey('concern-${pageItems[i].id}'),
          concern: pageItems[i],
          showDivider: i < pageItems.length - 1,
          onOpen: () => _open(pageItems[i]),
          endorsed: widget.endorsedConcernIds.contains(pageItems[i].id),
          onEndorse: widget.onEndorse == null
              ? null
              : () => widget.onEndorse!(pageItems[i]),
        ),
    ];

    return TitledTableCard(
      title: 'Concerns',
      subtitle: Text(
        '$total ${total == 1 ? 'concern' : 'concerns'}'
        '${waiting > 0 ? ' | $waiting waiting' : ''}'
        '${urgent > 0 ? ' | $urgent urgent' : ''}',
        style: TitledTableCard.subtitleStyle(context,
            color: DisciplineOfficerColors.placeholderText(context)),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: DashboardSearchField(
              key: const Key('concerns-search'),
              controller: _searchController,
              hint: 'Search student, sender or concern',
              fillColor: DisciplineOfficerColors.background(context),
              textColor: DisciplineOfficerColors.rowText(context),
              hintColor: DisciplineOfficerColors.placeholderText(context),
              onChanged: (value) => setState(() {
                _query = value;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: 10),
          FilterMenuButton(
            compact: true,
            backgroundColor: DisciplineOfficerColors.background(context),
            menuColor: DisciplineOfficerColors.card(context),
            borderColor: DisciplineOfficerColors.cardBorder(context),
            iconColor: DisciplineOfficerColors.placeholderText(context),
            textColor: DisciplineOfficerColors.rowText(context),
            mutedTextColor: DisciplineOfficerColors.placeholderText(context),
            accentColor: DisciplineOfficerColors.azureBlue,
            sections: [
              FilterMenuSection(
                title: 'Status',
                options: const [
                  FilterMenuOption(label: 'Pending', value: 'Pending'),
                  FilterMenuOption(label: 'In progress', value: 'In_Progress'),
                  FilterMenuOption(label: 'Closed', value: 'Closed'),
                ],
                selectedValue: _statusFilter,
                onChanged: (value) => setState(() {
                  _statusFilter = value;
                  _currentPage = 1;
                }),
              ),
            ],
          ),
        ],
      ),
      columns: _columns,
      rows: rows,
      empty: DashboardTableEmptyState(
        icon: Icons.volunteer_activism_outlined,
        message: widget.concerns.isEmpty
            ? 'No concerns yet'
            : 'No concerns match your search',
      ),
      footer: filtered.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: filtered.length,
              textColor: DisciplineOfficerColors.placeholderText(context),
              accentColor: DisciplineOfficerColors.azureBlue,
              mutedBackground: DisciplineOfficerColors.background(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
      backgroundColor: DisciplineOfficerColors.card(context),
      borderColor: DisciplineOfficerColors.cardBorder(context),
      titleColor: DisciplineOfficerColors.rowText(context),
    );
  }
}

class _ConcernRow extends StatelessWidget {
  const _ConcernRow({
    super.key,
    required this.concern,
    required this.showDivider,
    required this.onOpen,
    required this.endorsed,
    required this.onEndorse,
  });

  final ConcernReportModel concern;
  final bool showDivider;
  final VoidCallback onOpen;
  final bool endorsed;
  final VoidCallback? onEndorse;

  @override
  Widget build(BuildContext context) {
    final r = concern;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    final Widget action;
    if (endorsed) {
      action = Align(
        alignment: Alignment.centerRight,
        child: Text('Endorsed', style: dashboardTableSubStyle(context)),
      );
    } else if (onEndorse != null && r.isOpen) {
      action = DashboardRowIconButton(
        key: ValueKey('endorse-concern-${r.id}'),
        icon: Icons.assignment_late_outlined,
        tooltip: 'Endorse to Guidance',
        onPressed: onEndorse,
      );
    } else {
      action = const SizedBox.shrink();
    }

    return DashboardTableRow(
      columns: _columns,
      showDivider: showDivider,
      onTap: onOpen,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(r.studentName, dashboardTablePrimaryStyle(context)),
            line(r.studentNumber, dashboardTableSubStyle(context)),
          ],
        ),
        line(r.concernLabel, dashboardTableBodyStyle(context)),
        line(
          r.aboutStudentName ?? '—',
          dashboardTableBodyStyle(context),
        ),
        line(formatDateTime12h(r.createdAt), dashboardTableMetaStyle(context)),
        line(
          r.isUrgent ? 'Urgent' : 'Routine',
          r.isUrgent
              ? dashboardTableBodyStyle(context).copyWith(
                  color: kDangerTextColor,
                  fontWeight: FontWeight.w700,
                )
              : dashboardTableBodyStyle(context),
        ),
        line(r.statusLabel, dashboardTableBodyStyle(context)),
        action,
      ],
    );
  }
}

class _ConcernDialog extends StatefulWidget {
  const _ConcernDialog({required this.concern, required this.canEdit});

  final ConcernReportModel concern;
  final bool canEdit;

  @override
  State<_ConcernDialog> createState() => _ConcernDialogState();
}

class _ConcernDialogState extends State<_ConcernDialog> {
  late String _status = widget.concern.status;
  late final TextEditingController _note =
      TextEditingController(text: widget.concern.handlerNote ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.concern;
    final body = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.placeholderText(context);

    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: muted)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 13.5, color: body)),
            ],
          ),
        );

    return AppPopup(
      title: 'Concern',
      subtitle: '${r.studentName} · ${r.studentNumber}',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: widget.canEdit ? 'Cancel' : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.canEdit)
          AppPopupPrimaryButton(
            key: const Key('concern-save'),
            label: 'Save',
            onPressed: () => Navigator.of(context)
                .pop((status: _status, note: _note.text.trim())),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          fact('Filed by', r.studentName),
          if (r.aboutStudentName != null) fact('About', r.aboutStudentName!),
          fact('Concern', r.concernLabel),
          fact('Priority', r.isUrgent ? 'Urgent' : 'Routine'),
          fact('Details', r.details),
          if (widget.canEdit) ...[
            const SizedBox(height: 4),
            AppPopupDropdown<String>(
              label: 'Status',
              value: _status,
              items: const [
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(
                    value: 'In_Progress', child: Text('In progress')),
                DropdownMenuItem(value: 'Closed', child: Text('Closed')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            const SizedBox(height: 12),
            AppPopupTextField(
              label: 'Note (visible to the student who filed it)',
              controller: _note,
              maxLines: 3,
            ),
          ] else if ((r.handlerNote ?? '').isNotEmpty)
            fact('Note', r.handlerNote!),
        ],
      ),
    );
  }
}
