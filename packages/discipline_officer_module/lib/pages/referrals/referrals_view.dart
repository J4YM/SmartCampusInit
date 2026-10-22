import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../../models/student_referral_model.dart';
import '../../theme/discipline_officer_colors.dart';

/// Width of the table's far-right action column.
const double _kActionColumnWidth = 44;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Concern', flex: 4, minWidth: 190),
  DashboardTableColumn('Filed By', flex: 3, minWidth: 170),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Priority', flex: 2, minWidth: 100),
  DashboardTableColumn('Status', flex: 2, minWidth: 120),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// The Discipline Officer's "Referrals" tab: support requests students filed
/// from their own dashboard, for themselves or for a classmate. Urgent and
/// still-open ones come first. A row opens the full referral, where the
/// officer sets the status and leaves a note the referrer can read; the icon
/// ending an open row endorses the student to the Guidance Associate.
class ReferralsView extends StatefulWidget {
  const ReferralsView({
    super.key,
    required this.referrals,
    this.onUpdate,
    this.onEndorse,
    this.endorsedReferralIds = const {},
  });

  final List<StudentReferralModel> referrals;

  /// Saves a status change / note. Null makes the tab read-only (demo).
  final Future<void> Function(
    StudentReferralModel referral, {
    required String status,
    String? note,
  })? onUpdate;

  /// Starts an endorsement for the referral's student. Null hides the action.
  final Future<void> Function(StudentReferralModel referral)? onEndorse;

  /// Referrals that already have an endorsement: they show "Endorsed" instead
  /// of the action.
  final Set<String> endorsedReferralIds;

  @override
  State<ReferralsView> createState() => _ReferralsViewState();
}

class _ReferralsViewState extends State<ReferralsView> {
  final _searchController = TextEditingController();
  String _query = '';

  /// `Pending`, `In_Progress` or `Closed`; null = every referral.
  String? _statusFilter;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Open before closed, urgent before routine, then newest first.
  List<StudentReferralModel> get _ordered {
    final list = [...widget.referrals];
    list.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<StudentReferralModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return _ordered.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.studentName.toLowerCase().contains(q) ||
          r.studentNumber.toLowerCase().contains(q) ||
          r.referredByName.toLowerCase().contains(q) ||
          r.concernLabel.toLowerCase().contains(q) ||
          r.details.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _open(StudentReferralModel r) async {
    final result = await showAppPopup<({String status, String note})>(
      context: context,
      builder: (_) =>
          _ReferralDialog(referral: r, canEdit: widget.onUpdate != null),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onUpdate!(r, status: result.status, note: result.note);
      messenger.showSnackBar(const SnackBar(content: Text('Referral updated.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not update the referral: $e')));
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

    final total = widget.referrals.length;
    final waiting = widget.referrals.where((r) => r.status == 'Pending').length;
    final urgent =
        widget.referrals.where((r) => r.isOpen && r.isUrgent).length;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _ReferralRow(
          key: ValueKey('referral-${pageItems[i].id}'),
          referral: pageItems[i],
          showDivider: i < pageItems.length - 1,
          onOpen: () => _open(pageItems[i]),
          endorsed: widget.endorsedReferralIds.contains(pageItems[i].id),
          onEndorse: widget.onEndorse == null
              ? null
              : () => widget.onEndorse!(pageItems[i]),
        ),
    ];

    return TitledTableCard(
      title: 'Referrals',
      subtitle: Text(
        '$total ${total == 1 ? 'referral' : 'referrals'}'
        '${waiting > 0 ? ' | $waiting waiting' : ''}'
        '${urgent > 0 ? ' | $urgent urgent' : ''}',
        style: TitledTableCard.subtitleStyle(context,
            color: DisciplineOfficerColors.placeholderText(context)),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: DashboardSearchField(
              key: const Key('referrals-search'),
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
        message: widget.referrals.isEmpty
            ? 'No referrals yet'
            : 'No referrals match your search',
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

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({
    super.key,
    required this.referral,
    required this.showDivider,
    required this.onOpen,
    required this.endorsed,
    required this.onEndorse,
  });

  final StudentReferralModel referral;
  final bool showDivider;
  final VoidCallback onOpen;
  final bool endorsed;
  final VoidCallback? onEndorse;

  @override
  Widget build(BuildContext context) {
    final r = referral;
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
        key: ValueKey('endorse-referral-${r.id}'),
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
          r.isSelf ? '${r.referredByName} (self)' : r.referredByName,
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

class _ReferralDialog extends StatefulWidget {
  const _ReferralDialog({required this.referral, required this.canEdit});

  final StudentReferralModel referral;
  final bool canEdit;

  @override
  State<_ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends State<_ReferralDialog> {
  late String _status = widget.referral.status;
  late final TextEditingController _note =
      TextEditingController(text: widget.referral.counselorNote ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.referral;
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
      title: 'Referral',
      subtitle: '${r.studentName} · ${r.studentNumber}',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: widget.canEdit ? 'Cancel' : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.canEdit)
          AppPopupPrimaryButton(
            key: const Key('referral-save'),
            label: 'Save',
            onPressed: () => Navigator.of(context)
                .pop((status: _status, note: _note.text.trim())),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          fact('Filed by',
              r.isSelf ? '${r.referredByName} (for themselves)' : r.referredByName),
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
          ] else if ((r.counselorNote ?? '').isNotEmpty)
            fact('Note', r.counselorNote!),
        ],
      ),
    );
  }
}
