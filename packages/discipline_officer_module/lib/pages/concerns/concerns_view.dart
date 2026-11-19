import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/availability_round_info.dart' show EndorsementActionException;
import '../../models/concern_case_file.dart';
import '../../models/concern_report_model.dart';
import '../../theme/discipline_officer_colors.dart';

/// Width of the table's far-right action column.
const double _kActionColumnWidth = 250;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Concern', flex: 4, minWidth: 190),
  DashboardTableColumn('About', flex: 3, minWidth: 170),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Priority', flex: 2, minWidth: 100),
  DashboardTableColumn('Status', flex: 2, minWidth: 120),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// The Discipline Officer's "Concerns" tab: concern reports students filed
/// from their own dashboard to Student Affairs. Urgent and
/// still-open ones come first. A row opens the full concern, where the
/// officer sets the status and leaves a note the student can read; the icon
/// ending an open row endorses the student to the Guidance Associate.
class ConcernsView extends StatefulWidget {
  const ConcernsView({
    super.key,
    required this.concerns,
    this.onUpdate,
    this.onEndorse,
    this.onSendToInvestigation,
    this.loadCaseFile,
    this.onScheduleMeeting,
    this.onSetMeetingOutcome,
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

  /// Sends the concern into the investigation due process (the officer names
  /// the student it is about). Null hides the action.
  final Future<void> Function(ConcernReportModel concern)?
      onSendToInvestigation;

  /// Loads what came back for a concern (endorsement meetings, investigation
  /// findings) for its dialog. Null hides the case file.
  final Future<ConcernCaseFile> Function(ConcernReportModel concern)?
      loadCaseFile;

  /// Schedules a Student Affairs-only meeting about the concern (no Guidance):
  /// when, where and who to invite. Null hides the action.
  final Future<void> Function(
    ConcernReportModel concern,
    MeetingFormResult meeting,
  )? onScheduleMeeting;

  /// Marks one of those meetings `Completed`, `Missed` or `Cancelled`.
  final Future<void> Function(CaseMeeting meeting, String status)?
      onSetMeetingOutcome;

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

  Future<void> _scheduleMeeting(ConcernReportModel r) async {
    final onSchedule = widget.onScheduleMeeting;
    if (onSchedule == null) return;
    final result = await showAppPopup<MeetingFormResult>(
      context: context,
      builder: (_) => ScheduleMeetingDialog(
        title: 'Schedule a meeting',
        subtitle: 'About the concern from ${r.studentName}. The invitee '
            'confirms or declines in their own dashboard.',
      ),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await onSchedule(r, result);
      messenger.showSnackBar(const SnackBar(
          content: Text('Meeting scheduled. The invitee has been notified.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e is EndorsementActionException
              ? e.message
              : 'Could not schedule the meeting. Please try again.')));
    }
  }

  Future<void> _open(ConcernReportModel r) async {
    final result = await showAppPopup<({String status, String note})>(
      context: context,
      builder: (_) => _ConcernDialog(
        concern: r,
        canEdit: widget.onUpdate != null,
        loadCaseFile: widget.loadCaseFile == null
            ? null
            : () => widget.loadCaseFile!(r),
        onSetMeetingOutcome: widget.onSetMeetingOutcome,
      ),
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
          onSendToInvestigation: widget.onSendToInvestigation == null
              ? null
              : () => widget.onSendToInvestigation!(pageItems[i]),
          onScheduleMeeting: widget.onScheduleMeeting == null
              ? null
              : () => _scheduleMeeting(pageItems[i]),
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
    this.onSendToInvestigation,
    this.onScheduleMeeting,
  });

  final ConcernReportModel concern;
  final bool showDivider;
  final VoidCallback onOpen;
  final bool endorsed;
  final VoidCallback? onEndorse;
  final VoidCallback? onSendToInvestigation;
  final VoidCallback? onScheduleMeeting;

  @override
  Widget build(BuildContext context) {
    final r = concern;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    // Every row keeps a way to open the concern (status picker + case file),
    // whatever has happened to it. The two process actions only apply while it
    // is open: endorsing once, and sending to investigation once.
    final canEndorse = !endorsed && onEndorse != null && r.isOpen;
    final canSend =
        !r.underInvestigation && onSendToInvestigation != null && r.isOpen;
    final Widget action = Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (endorsed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('Endorsed', style: dashboardTableSubStyle(context)),
            )
          else if (canEndorse)
            DashboardRowIconButton(
              key: ValueKey('endorse-concern-${r.id}'),
              icon: Icons.assignment_late_outlined,
              tooltip: 'Endorse to Guidance',
              onPressed: onEndorse,
            ),
          if (r.underInvestigation)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('Under investigation',
                  style: dashboardTableSubStyle(context)),
            )
          else if (canSend)
            DashboardRowIconButton(
              key: ValueKey('send-to-investigation-${r.id}'),
              icon: Icons.manage_search_rounded,
              tooltip: 'Send to investigation',
              onPressed: onSendToInvestigation,
            ),
          if (r.isOpen && onScheduleMeeting != null)
            DashboardRowIconButton(
              key: ValueKey('schedule-concern-meeting-${r.id}'),
              icon: Icons.event_available_outlined,
              tooltip: 'Schedule a meeting',
              onPressed: onScheduleMeeting,
            ),
          DashboardRowIconButton(
            key: ValueKey('manage-concern-${r.id}'),
            icon: Icons.tune_rounded,
            tooltip: 'Open concern',
            onPressed: onOpen,
          ),
        ],
      ),
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
          r.aboutStudentName ?? '—',
          dashboardTableBodyStyle(context),
        ),
        line(formatDateTime12h(r.createdAt), dashboardTableMetaStyle(context)),
        _ConcernPill(
          key: ValueKey('concern-priority-${r.id}'),
          label: r.isUrgent ? 'Urgent' : 'Routine',
          color: r.isUrgent ? DisciplineOfficerColors.denyRed : _slate,
        ),
        _ConcernPill(
          key: ValueKey('concern-status-${r.id}'),
          label: r.statusLabel,
          color: switch (r.status) {
            'In_Progress' => DisciplineOfficerColors.azureBlue,
            'Closed' => DisciplineOfficerColors.validateGreen,
            _ => _amber,
          },
        ),
        action,
      ],
    );
  }
}

const _slate = Color(0xFF64748B);
const _amber = Color(0xFFD97706);

/// A soft status pill for the Priority and Status columns: the same look as the
/// Endorsement and Investigation badges (pill radius, 14% tint of its color,
/// 11px w600).
class _ConcernPill extends StatelessWidget {
  const _ConcernPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ),
    );
  }
}

class _ConcernDialog extends StatefulWidget {
  const _ConcernDialog({
    required this.concern,
    required this.canEdit,
    this.loadCaseFile,
    this.onSetMeetingOutcome,
  });

  final ConcernReportModel concern;
  final bool canEdit;
  final Future<ConcernCaseFile> Function()? loadCaseFile;
  final Future<void> Function(CaseMeeting meeting, String status)?
      onSetMeetingOutcome;

  @override
  State<_ConcernDialog> createState() => _ConcernDialogState();
}

class _ConcernDialogState extends State<_ConcernDialog> {
  late String _status = widget.concern.status;
  late final TextEditingController _note =
      TextEditingController(text: widget.concern.handlerNote ?? '');
  late Future<ConcernCaseFile>? _caseFile = widget.loadCaseFile?.call();

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
          if (_caseFile != null)
            _CaseFileSection(
              future: _caseFile!,
              onSetMeetingOutcome: widget.onSetMeetingOutcome,
              onChanged: () =>
                  setState(() => _caseFile = widget.loadCaseFile?.call()),
            ),
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

/// What came back for a concern: Guidance's endorsement meetings and the
/// investigation's findings. Loads when the dialog opens; a failure is shown
/// without blocking the status picker.
class _CaseFileSection extends StatelessWidget {
  const _CaseFileSection({
    required this.future,
    this.onSetMeetingOutcome,
    this.onChanged,
  });

  final Future<ConcernCaseFile> future;
  final Future<void> Function(CaseMeeting meeting, String status)?
      onSetMeetingOutcome;

  /// Called after an outcome is saved so the section reloads.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final body = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.placeholderText(context);

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(t,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: body)),
        );
    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: muted)),
              Text(value, style: TextStyle(fontSize: 13, color: body)),
            ],
          ),
        );

    return FutureBuilder<ConcernCaseFile>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Loading the case file…',
                style: TextStyle(fontSize: 12, color: muted)),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Could not load the case file: ${snap.error}',
                style: TextStyle(
                    fontSize: 12, color: DisciplineOfficerColors.denyRed)),
          );
        }
        final file = snap.data!;
        if (file.isEmpty) return const SizedBox.shrink();
        final inv = file.investigation;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in file.endorsements) ...[
              heading('Endorsed to Guidance · ${_endorsementLabel(e.status)}'),
              if ((e.decisionNote ?? '').isNotEmpty)
                fact('Guidance note', e.decisionNote!),
              for (final m in e.meetings) ...[
                fact(
                  'Meeting · ${m.status.replaceAll('_', ' ')}',
                  '${formatDateTime12h(m.scheduledAt)}'
                  '${(m.location ?? '').isEmpty ? '' : ' · ${m.location}'}',
                ),
                if ((m.responseNote ?? '').isNotEmpty)
                  fact('Reply to the invitation', m.responseNote!),
                if ((m.guidanceNote ?? '').isNotEmpty)
                  fact('Guidance recommendation', m.guidanceNote!),
              ],
            ],
            if (file.meetings.isNotEmpty) ...[
              heading('Meetings with Student Affairs'),
              for (final m in file.meetings) ...[
                fact(
                  'Student Affairs meeting · ${m.status.replaceAll('_', ' ')}',
                  '${formatDateTime12h(m.scheduledAt)}'
                  '${(m.location ?? '').isEmpty ? '' : ' · ${m.location}'}'
                  '${m.invitee == null ? '' : ' · ${_inviteeLabel(m.invitee!)}'}',
                ),
                if ((m.responseNote ?? '').isNotEmpty)
                  fact('Reply to the invitation', m.responseNote!),
                if (onSetMeetingOutcome != null &&
                    _openMeetingStatuses.contains(m.status))
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final status in const ['Completed', 'Missed', 'Cancelled'])
                        OutlinedButton(
                          key: Key('concern-meeting-outcome-${m.id}-$status'),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await onSetMeetingOutcome!(m, status);
                              onChanged?.call();
                            } catch (e) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text(e is EndorsementActionException
                                      ? e.message
                                      : 'Could not update the meeting.')));
                            }
                          },
                          child: Text(status),
                        ),
                    ],
                  ),
              ],
            ],
            if (inv != null) ...[
              heading(
                  'Investigation · ${inv.status == 'Complete' ? 'Complete' : 'Open'}'),
              if (inv.outcome != null)
                fact('Verdict',
                    inv.outcome == 'Proven' ? 'Proven' : 'Not proven'),
              if ((inv.findings ?? '').isNotEmpty)
                fact('Findings', inv.findings!),
              if ((inv.recommendation ?? '').isNotEmpty)
                fact('Recommendation', inv.recommendation!),
              if (inv.sanctionDescription != null)
                fact(
                  'Sanction',
                  '${inv.sanctionType ?? ''}'
                  '${inv.sanctionType == null ? '' : ': '}'
                  '${inv.sanctionDescription}',
                ),
            ],
            const Divider(height: 20),
          ],
        );
      },
    );
  }

  /// Meetings still waiting to happen: the officer can close them out.
  static const _openMeetingStatuses = {
    'Proposed',
    'Confirmed',
    'Declined',
    'Reschedule_Requested',
  };

  static String _inviteeLabel(String invitee) => switch (invitee) {
        'both' => 'student and parent',
        'parent' => 'parent',
        _ => 'student',
      };

  static String _endorsementLabel(String status) => switch (status) {
        'Approved' => 'accepted',
        'Rejected' => 'declined',
        _ => 'waiting for Guidance',
      };
}
