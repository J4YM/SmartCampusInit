import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../shared/guidance_tab_chrome.dart';

/// One student referral (supabase/add_student_referrals.sql) as the
/// Guidance Counselor sees it: who it is about, who filed it, and where it
/// stands. Staff see the referrer; the referred student never does.
class StudentReferralModel {
  const StudentReferralModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.referredByName,
    required this.isSelf,
    required this.concern,
    required this.details,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.counselorNote,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String referredByName;
  final bool isSelf;

  /// `student_referrals.concern` key, e.g. `emotional`.
  final String concern;
  final String details;
  final String urgency;

  /// `Pending`, `In_Progress` or `Closed`.
  final String status;
  final DateTime createdAt;
  final String? counselorNote;

  bool get isUrgent => urgency == 'Urgent';
  bool get isOpen => status != 'Closed';

  String get concernLabel => switch (concern) {
        'academic' => 'Academic difficulties',
        'attendance' => 'Attendance',
        'behavior' => 'Behavior',
        'emotional' => 'Emotional / mental well-being',
        'family' => 'Family or home situation',
        'bullying' => 'Bullying',
        'safety' => 'Safety',
        _ => 'Other',
      };

  String get statusLabel => switch (status) {
        'In_Progress' => 'In progress',
        'Closed' => 'Closed',
        _ => 'Pending',
      };
}

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Concern', flex: 4, minWidth: 190),
  DashboardTableColumn('Filed By', flex: 3, minWidth: 170),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Priority', flex: 2, minWidth: 100),
  DashboardTableColumn('Status', flex: 2, minWidth: 120),
];

/// Guidance Counselor's "Referrals" tab: support requests students filed from
/// their own dashboard, for themselves or for a classmate. Urgent and
/// still-open ones come first. A row opens the full referral, where the
/// counselor sets the status and leaves a note the referrer can read.
class ReferralsView extends StatefulWidget {
  const ReferralsView({super.key, required this.referrals, this.onUpdate});

  final List<StudentReferralModel> referrals;

  /// Saves a status change / note. Null makes the tab read-only (demo).
  final Future<void> Function(
    StudentReferralModel referral, {
    required String status,
    String? note,
  })? onUpdate;

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
        ),
    ];

    return GuidanceTableCard(
      title: 'Referrals',
      subtitle: Text(
        '$total ${total == 1 ? 'referral' : 'referrals'}'
        '${waiting > 0 ? ' | $waiting waiting' : ''}'
        '${urgent > 0 ? ' | $urgent urgent' : ''}',
        style: GuidanceTableCard.subtitleStyle(context),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: GuidanceSearchField(
              key: const Key('referrals-search'),
              controller: _searchController,
              hint: 'Search student, sender or concern',
              onChanged: (value) => setState(() {
                _query = value;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: 10),
          FilterMenuButton(
            compact: true,
            backgroundColor: GuidanceTabColors.searchFill(context),
            menuColor: GuidanceTabColors.card(context),
            borderColor: GuidanceTabColors.cardBorder(context),
            iconColor: GuidanceTabColors.mutedIcon(context),
            textColor: GuidanceTabColors.primaryText(context),
            mutedTextColor: GuidanceTabColors.secondaryText(context),
            accentColor: GuidanceTabColors.primaryAction,
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
              textColor: GuidanceTabColors.secondaryText(context),
              accentColor: GuidanceTabColors.primaryAction,
              mutedBackground: GuidanceTabColors.surfaceBackground(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
    );
  }
}

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({
    super.key,
    required this.referral,
    required this.showDivider,
    required this.onOpen,
  });

  final StudentReferralModel referral;
  final bool showDivider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

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
    final body = GuidanceTabColors.primaryText(context);
    final muted = GuidanceTabColors.secondaryText(context);

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
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
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
