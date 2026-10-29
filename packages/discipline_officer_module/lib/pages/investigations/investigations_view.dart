import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/discipline_officer_colors.dart';

/// One meeting the officer set up for an investigation, with the invitee's
/// answer (`guidance_meetings`, see supabase/add_guidance_investigations.sql).
class InvestigationMeetingModel {
  const InvestigationMeetingModel({
    required this.id,
    required this.scheduledAt,
    required this.invitee,
    required this.status,
    this.location,
    this.responseNote,
  });

  final String id;
  final DateTime scheduledAt;

  /// `student`, `parent` or `both`.
  final String invitee;

  /// `Proposed`, `Confirmed`, `Declined`, `Reschedule_Requested`, `Completed`,
  /// `Missed` or `Cancelled`.
  final String status;
  final String? location;
  final String? responseNote;

  /// No further changes: it happened, was missed or was cancelled.
  bool get isFinished =>
      status == 'Completed' || status == 'Missed' || status == 'Cancelled';

  /// Still expected to take place.
  bool get isUpcoming =>
      status == 'Proposed' || status == 'Confirmed';

  String get statusLabel => switch (status) {
        'Reschedule_Requested' => 'Reschedule requested',
        _ => status,
      };

  String get inviteeLabel => switch (invitee) {
        'student' => 'Student',
        'parent' => 'Parent',
        _ => 'Student & parent',
      };
}

/// A case under investigation by the Discipline Office.
class InvestigationModel {
  const InvestigationModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.offenseLabel,
    required this.incidentNotes,
    required this.createdAt,
    required this.status,
    required this.meetings,
    required this.evidencePaths,
    this.offenseCategory,
    this.incidentAt,
    this.findings,
    this.recommendation,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final String offenseLabel;
  final String? offenseCategory;
  final String incidentNotes;
  final DateTime? incidentAt;
  final DateTime createdAt;

  /// `Open` or `Complete`.
  final String status;
  final List<InvestigationMeetingModel> meetings;
  final List<String> evidencePaths;
  final String? findings;
  final String? recommendation;

  bool get isOpen => status == 'Open';

  /// An open investigation with no meeting still expected to happen.
  bool get needsMeeting => isOpen && !meetings.any((m) => m.isUpcoming);
}

const double _kActionColumnWidth = 108;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Violation', flex: 4, minWidth: 220),
  DashboardTableColumn('Meeting', flex: 4, minWidth: 210),
  DashboardTableColumn('Status', flex: 2, minWidth: 110),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// The Discipline Officer's "Investigations" tab: cases under investigation.
/// For each, the officer schedules a meeting with the student and/or parent
/// (who confirm or decline from their own dashboard), records how it went,
/// and files findings, after which the case can be sanctioned.
///
/// A table like every other DO tab; a row (or its eye button) opens the
/// whole case — incident, photo evidence, meetings and findings — in a popup.
class InvestigationsView extends StatefulWidget {
  const InvestigationsView({
    super.key,
    required this.investigations,
    this.onSchedule,
    this.onSetMeetingOutcome,
    this.onComplete,
    this.onLoadEvidence,
  });

  final List<InvestigationModel> investigations;

  /// Schedules a meeting: when, where (nullable) and who (`student`,
  /// `parent`, `both`). Null makes the tab read-only (demo).
  final Future<void> Function(
    InvestigationModel investigation,
    DateTime scheduledAt,
    String? location,
    String invitee,
  )? onSchedule;

  /// Marks a meeting `Completed`, `Missed` or `Cancelled`.
  final Future<void> Function(InvestigationMeetingModel meeting, String status)?
      onSetMeetingOutcome;

  /// Files findings (and an optional recommendation) and completes the case.
  final Future<void> Function(
    InvestigationModel investigation,
    String findings,
    String? recommendation,
  )? onComplete;

  /// Signed viewing links for evidence photos, keyed by storage path.
  final Future<Map<String, String>> Function(List<String> paths)?
      onLoadEvidence;

  @override
  State<InvestigationsView> createState() => _InvestigationsViewState();
}

/// What the details popup asks the tab to do once it closes.
typedef _DetailResult = ({
  String kind, // 'schedule' | 'complete' | 'outcome'
  InvestigationMeetingModel? meeting,
  String? status,
});

class _InvestigationsViewState extends State<InvestigationsView> {
  final _search = TextEditingController();
  String _query = '';

  /// `Open` or `Complete`; null = every investigation.
  String? _statusFilter;
  int _currentPage = 1;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Open before complete, then newest first.
  List<InvestigationModel> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = widget.investigations.where((i) {
      if (_statusFilter == 'Open' && !i.isOpen) return false;
      if (_statusFilter == 'Complete' && i.isOpen) return false;
      if (q.isEmpty) return true;
      return i.studentName.toLowerCase().contains(q) ||
          i.studentNumber.toLowerCase().contains(q) ||
          i.offenseLabel.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule(InvestigationModel inv) async {
    final result = await showAppPopup<MeetingFormResult>(
      context: context,
      builder: (_) => const ScheduleMeetingDialog(),
    );
    final onSchedule = widget.onSchedule;
    if (result == null || onSchedule == null || !mounted) return;
    await _run(
      () => onSchedule(inv, result.scheduledAt, result.location, result.invitee),
      'Meeting scheduled. The invitee has been notified.',
    );
  }

  Future<void> _complete(InvestigationModel inv) async {
    final result =
        await showAppPopup<({String findings, String? recommendation})>(
      context: context,
      builder: (_) => CompleteInvestigationDialog(studentName: inv.studentName),
    );
    final onComplete = widget.onComplete;
    if (result == null || onComplete == null || !mounted) return;
    await _run(
      () => onComplete(inv, result.findings, result.recommendation),
      'Investigation complete. You can now sanction the case.',
    );
  }

  Future<void> _outcome(InvestigationMeetingModel m, String status) async {
    final onOutcome = widget.onSetMeetingOutcome;
    if (onOutcome == null) return;
    await _run(() => onOutcome(m, status),
        'Meeting marked ${status.toLowerCase()}.');
  }

  Future<void> _openDetails(InvestigationModel inv) async {
    final result = await showAppPopup<_DetailResult>(
      context: context,
      builder: (_) => _InvestigationDetailDialog(
        investigation: inv,
        canSchedule: widget.onSchedule != null,
        canComplete: widget.onComplete != null,
        canEditMeetings: widget.onSetMeetingOutcome != null,
        onLoadEvidence: widget.onLoadEvidence,
      ),
    );
    if (result == null || !mounted) return;
    switch (result.kind) {
      case 'schedule':
        await _schedule(inv);
      case 'complete':
        await _complete(inv);
      case 'outcome':
        await _outcome(result.meeting!, result.status!);
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

    final total = widget.investigations.length;
    final open = widget.investigations.where((i) => i.isOpen).length;
    final needMeeting =
        widget.investigations.where((i) => i.needsMeeting).length;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _InvestigationRow(
          key: ValueKey('investigation-${pageItems[i].id}'),
          investigation: pageItems[i],
          showDivider: i < pageItems.length - 1,
          busy: _busy,
          onOpen: () => _openDetails(pageItems[i]),
          onSchedule: widget.onSchedule != null && pageItems[i].needsMeeting
              ? () => _schedule(pageItems[i])
              : null,
          scheduleTooltip: pageItems[i].meetings.isEmpty
              ? 'Schedule meeting'
              : 'Reschedule meeting',
          onComplete: widget.onComplete != null && pageItems[i].isOpen
              ? () => _complete(pageItems[i])
              : null,
        ),
    ];

    return TitledTableCard(
      title: 'Investigations',
      subtitle: Text(
        '$total ${total == 1 ? 'investigation' : 'investigations'}'
        ' | $open open'
        '${needMeeting > 0 ? ' | $needMeeting need a meeting' : ''}',
        style: TitledTableCard.subtitleStyle(context,
            color: DisciplineOfficerColors.placeholderText(context)),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: DashboardSearchField(
              key: const Key('investigations-search'),
              controller: _search,
              hint: 'Search student or violation',
              fillColor: DisciplineOfficerColors.background(context),
              textColor: DisciplineOfficerColors.rowText(context),
              hintColor: DisciplineOfficerColors.placeholderText(context),
              onChanged: (v) => setState(() {
                _query = v;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: 10),
          FilterMenuButton(
            key: const Key('investigations-filter'),
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
                  FilterMenuOption(label: 'Open', value: 'Open'),
                  FilterMenuOption(label: 'Complete', value: 'Complete'),
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
        icon: Icons.manage_search_rounded,
        message: widget.investigations.isEmpty
            ? 'No investigations yet'
            : 'No investigations match your search',
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

/// A soft status pill — the same look as the Escalation / Referral badges
/// (pill radius, 14% tint of its color, 11px w600).
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

const _green = Color(0xFF2E9E6A);
const _red = Color(0xFFCD4855);
const _amber = Color(0xFFD97706);
const _slate = Color(0xFF64748B);

Color _meetingColor(String status) => switch (status) {
      'Confirmed' || 'Completed' => _green,
      'Declined' || 'Missed' || 'Cancelled' => _red,
      'Reschedule_Requested' => _amber,
      _ => _slate,
    };

class _InvestigationRow extends StatelessWidget {
  const _InvestigationRow({
    super.key,
    required this.investigation,
    required this.showDivider,
    required this.busy,
    required this.onOpen,
    required this.onSchedule,
    required this.scheduleTooltip,
    required this.onComplete,
  });

  final InvestigationModel investigation;
  final bool showDivider;
  final bool busy;
  final VoidCallback onOpen;

  /// Null hides the button (read-only, or a meeting is already pending).
  final VoidCallback? onSchedule;
  final String scheduleTooltip;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final inv = investigation;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    // The most recent meeting stands for the case: when it is and how the
    // invitee answered.
    InvestigationMeetingModel? latest;
    for (final m in inv.meetings) {
      if (latest == null || m.scheduledAt.isAfter(latest.scheduledAt)) latest = m;
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
            line(inv.studentName, dashboardTablePrimaryStyle(context)),
            line('${inv.studentNumber} · ${inv.section}',
                dashboardTableSubStyle(context)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(inv.offenseLabel, dashboardTableBodyStyle(context)),
            if (inv.incidentAt != null)
              line(formatDateTime12h(inv.incidentAt!),
                  dashboardTableMetaStyle(context)),
          ],
        ),
        if (latest == null)
          line('No meeting yet', dashboardTableMetaStyle(context))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line(formatDateTime12h(latest.scheduledAt),
                  dashboardTableBodyStyle(context)),
              const SizedBox(height: 3),
              _StatusPill(latest.statusLabel, _meetingColor(latest.status),
                  key: Key('meeting-status-${latest.id}')),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: _StatusPill(
            inv.isOpen ? 'Open' : 'Complete',
            inv.isOpen ? _amber : _green,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardRowIconButton(
                key: ValueKey('investigation-view-${inv.id}'),
                icon: Icons.visibility_outlined,
                tooltip: 'View case',
                onPressed: onOpen,
              ),
              if (onSchedule != null)
                DashboardRowIconButton(
                  key: Key('schedule-meeting-${inv.id}'),
                  icon: Icons.event_available_outlined,
                  tooltip: scheduleTooltip,
                  onPressed: busy ? null : onSchedule,
                ),
              if (onComplete != null)
                DashboardRowIconButton(
                  key: Key('complete-investigation-${inv.id}'),
                  icon: Icons.task_alt_rounded,
                  tooltip: 'Complete investigation',
                  onPressed: busy ? null : onComplete,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Popups
// ---------------------------------------------------------------------------

/// The whole case: incident and notes, photo evidence, every meeting with the
/// invitee's answer, and — once complete — the findings.
class _InvestigationDetailDialog extends StatefulWidget {
  const _InvestigationDetailDialog({
    required this.investigation,
    required this.canSchedule,
    required this.canComplete,
    required this.canEditMeetings,
    required this.onLoadEvidence,
  });

  final InvestigationModel investigation;
  final bool canSchedule;
  final bool canComplete;
  final bool canEditMeetings;
  final Future<Map<String, String>> Function(List<String> paths)?
      onLoadEvidence;

  @override
  State<_InvestigationDetailDialog> createState() =>
      _InvestigationDetailDialogState();
}

class _InvestigationDetailDialogState
    extends State<_InvestigationDetailDialog> {
  Map<String, String> _urls = const {};

  @override
  void initState() {
    super.initState();
    _loadEvidence();
  }

  Future<void> _loadEvidence() async {
    final loader = widget.onLoadEvidence;
    final paths = widget.investigation.evidencePaths;
    if (loader == null || paths.isEmpty) return;
    try {
      final urls = await loader(paths);
      if (mounted) setState(() => _urls = urls);
    } catch (e) {
      debugPrint('Could not load evidence photos: $e');
    }
  }

  void _close(String kind, {InvestigationMeetingModel? meeting, String? status}) =>
      Navigator.of(context).pop<_DetailResult>(
          (kind: kind, meeting: meeting, status: status));

  @override
  Widget build(BuildContext context) {
    final inv = widget.investigation;
    final c = AppPopupColors.of(context);
    final open = inv.isOpen;
    final meetings = [...inv.meetings]
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    TextStyle text({double size = 12.5, FontWeight? weight, Color? color}) =>
        GoogleFonts.poppins(
            fontSize: size, fontWeight: weight, color: color ?? c.text);

    return AppPopup(
      title: 'Investigation',
      subtitle: '${inv.studentName} · ${inv.studentNumber} · ${inv.section}',
      width: 580,
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (open && widget.canSchedule && inv.needsMeeting)
          AppPopupSecondaryButton(
            key: const Key('detail-schedule'),
            label: inv.meetings.isEmpty ? 'Schedule meeting' : 'Reschedule meeting',
            icon: Icons.event_available_outlined,
            onPressed: () => _close('schedule'),
          ),
        if (open && widget.canComplete)
          AppPopupPrimaryButton(
            key: const Key('detail-complete'),
            label: 'Complete investigation',
            icon: Icons.task_alt_rounded,
            onPressed: () => _close('complete'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppPopupSection('Incident', icon: Icons.report_gmailerrorred_outlined),
          Text(inv.offenseLabel,
              style: text(size: 13, weight: FontWeight.w600)),
          if (inv.incidentAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Incident: ${formatDateTime12h(inv.incidentAt!)}',
                  style: text(size: 11.5, color: c.muted)),
            ),
          if (inv.incidentNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(inv.incidentNotes, style: text()),
            ),
          if (inv.evidencePaths.isNotEmpty) ...[
            const SizedBox(height: 14),
            AppPopupSection('Photo evidence (${inv.evidencePaths.length})',
                icon: Icons.photo_library_outlined),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in inv.evidencePaths) _Thumb(url: _urls[p]),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const AppPopupSection('Meetings', icon: Icons.event_outlined),
          if (meetings.isEmpty)
            Text('No meeting scheduled yet.',
                style: text(color: c.muted))
          else
            for (final m in meetings)
              _MeetingRow(
                meeting: m,
                canEdit: open && widget.canEditMeetings,
                onOutcome: (s) => _close('outcome', meeting: m, status: s),
              ),
          if (!open && (inv.findings ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            const AppPopupSection('Findings', icon: Icons.fact_check_outlined),
            Text(inv.findings!, style: text()),
            if ((inv.recommendation ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Recommendation: ${inv.recommendation}',
                    style: text(size: 12, color: c.muted)),
              ),
          ],
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.meeting,
    required this.canEdit,
    required this.onOutcome,
  });

  final InvestigationMeetingModel meeting;
  final bool canEdit;
  final ValueChanged<String> onOutcome;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final note = (meeting.responseNote ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.fieldFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime12h(meeting.scheduledAt) +
                      (meeting.location == null ? '' : ' · ${meeting.location}'),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text),
                ),
                Text('Invited: ${meeting.inviteeLabel}',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted)),
                if (note.isNotEmpty)
                  Text('Reply: $note',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted)),
                // Under the details (not beside them), so a long status such as
                // "Reschedule requested" never squeezes the text on a phone.
                const SizedBox(height: 6),
                _StatusPill(meeting.statusLabel, _meetingColor(meeting.status)),
              ],
            ),
          ),
          if (canEdit && !meeting.isFinished)
            PopupMenuButton<String>(
              key: Key('meeting-menu-${meeting.id}'),
              tooltip: 'Meeting outcome',
              icon: Icon(Icons.more_vert_rounded, size: 20, color: c.muted),
              color: c.card,
              onSelected: onOutcome,
              itemBuilder: (_) => [
                for (final (value, label) in const [
                  ('Completed', 'Mark completed'),
                  ('Missed', 'Mark missed'),
                  ('Cancelled', 'Cancel meeting'),
                ])
                  PopupMenuItem(
                    value: value,
                    child: Text(label,
                        style: GoogleFonts.poppins(fontSize: 13, color: c.text)),
                  ),
              ],
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final placeholder = Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.fieldFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.image_outlined, color: c.muted),
    );
    final link = url;
    if (link == null) return placeholder;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showAppPopup<void>(
        context: context,
        builder: (dialogContext) => AppPopup(
          title: 'Photo evidence',
          width: 640,
          actions: [
            AppPopupSecondaryButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          body: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InteractiveViewer(child: Image.network(link)),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(link,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder),
      ),
    );
  }
}

/// File findings (required) and an optional recommendation to complete the
/// investigation.
class CompleteInvestigationDialog extends StatefulWidget {
  const CompleteInvestigationDialog({super.key, required this.studentName});

  final String studentName;

  @override
  State<CompleteInvestigationDialog> createState() =>
      _CompleteInvestigationDialogState();
}

class _CompleteInvestigationDialogState
    extends State<CompleteInvestigationDialog> {
  final _findings = TextEditingController();
  final _recommendation = TextEditingController();

  @override
  void dispose() {
    _findings.dispose();
    _recommendation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _findings.text.trim().isNotEmpty;
    return AppPopup(
      title: 'Complete Investigation',
      subtitle: '${widget.studentName} · findings go back to the Discipline Officer',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('complete-save'),
          label: 'Complete',
          onPressed: canSave
              ? () {
                  final rec = _recommendation.text.trim();
                  Navigator.of(context).pop((
                    findings: _findings.text.trim(),
                    recommendation: rec.isEmpty ? null : rec,
                  ));
                }
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPopupTextField(
            label: 'Findings',
            fieldKey: const Key('findings-field'),
            controller: _findings,
            minLines: 4,
            maxLines: 7,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          AppPopupTextField(
            label: 'Recommendation (optional)',
            fieldKey: const Key('recommendation-field'),
            controller: _recommendation,
            minLines: 2,
            maxLines: 4,
          ),
        ],
      ),
    );
  }
}
