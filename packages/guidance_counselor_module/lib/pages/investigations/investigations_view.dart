import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/guidance_tab_chrome.dart';

/// One meeting the counselor set up for an investigation, with the invitee's
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

/// A case sent to Guidance by the Discipline Officer.
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

/// Null when [when] is acceptable for a meeting; otherwise the message.
String? validateMeetingTime(DateTime when, {DateTime? now}) =>
    when.isAfter(now ?? DateTime.now()) ? null : 'Choose a time in the future.';

/// Guidance Counselor's "Investigations" tab: cases the Discipline Officer
/// escalated. For each, the counselor schedules a meeting with the student
/// and/or parent (who confirm or decline from their own dashboard), records
/// how it went, and files findings, which returns the case to the officer.
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

class _InvestigationsViewState extends State<InvestigationsView> {
  final _search = TextEditingController();
  String _query = '';
  bool _openOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<InvestigationModel> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = widget.investigations.where((i) {
      if (_openOnly && !i.isOpen) return false;
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final open = widget.investigations.where((i) => i.isOpen).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Investigations',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: GuidanceTabColors.primaryText(context),
                ),
              ),
            ),
            Text(
              '$open open | ${widget.investigations.length} total',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: GuidanceTabColors.secondaryText(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GuidanceSearchField(
                key: const Key('investigations-search'),
                controller: _search,
                hint: 'Search student or violation',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 10),
            FilterChip(
              key: const Key('investigations-open-only'),
              label: const Text('Open only'),
              selected: _openOnly,
              onSelected: (v) => setState(() => _openOnly = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: DashboardTableEmptyState(
              icon: Icons.manage_search_rounded,
              message: widget.investigations.isEmpty
                  ? 'No investigations yet'
                  : 'No investigations match your search',
            ),
          )
        else
          for (final i in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _InvestigationCard(
                key: ValueKey('investigation-card-${i.id}'),
                investigation: i,
                view: widget,
              ),
            ),
      ],
    );
  }
}

class _InvestigationCard extends StatefulWidget {
  const _InvestigationCard({
    super.key,
    required this.investigation,
    required this.view,
  });

  final InvestigationModel investigation;
  final InvestigationsView view;

  @override
  State<_InvestigationCard> createState() => _InvestigationCardState();
}

class _InvestigationCardState extends State<_InvestigationCard> {
  Map<String, String> _urls = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadEvidence();
  }

  Future<void> _loadEvidence() async {
    final loader = widget.view.onLoadEvidence;
    final paths = widget.investigation.evidencePaths;
    if (loader == null || paths.isEmpty) return;
    try {
      final urls = await loader(paths);
      if (mounted) setState(() => _urls = urls);
    } catch (e) {
      debugPrint('Could not load evidence photos: $e');
    }
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

  Future<void> _schedule() async {
    final inv = widget.investigation;
    final result = await showAppPopup<MeetingFormResult>(
      context: context,
      builder: (_) => const ScheduleMeetingDialog(),
    );
    final onSchedule = widget.view.onSchedule;
    if (result == null || onSchedule == null || !mounted) return;
    await _run(
      () => onSchedule(inv, result.scheduledAt, result.location, result.invitee),
      'Meeting scheduled. The invitee has been notified.',
    );
  }

  Future<void> _complete() async {
    final inv = widget.investigation;
    final result = await showAppPopup<({String findings, String? recommendation})>(
      context: context,
      builder: (_) => CompleteInvestigationDialog(studentName: inv.studentName),
    );
    final onComplete = widget.view.onComplete;
    if (result == null || onComplete == null || !mounted) return;
    await _run(
      () => onComplete(inv, result.findings, result.recommendation),
      'Investigation complete. The Discipline Officer can now sanction the case.',
    );
  }

  Future<void> _outcome(InvestigationMeetingModel m, String status) async {
    final onOutcome = widget.view.onSetMeetingOutcome;
    if (onOutcome == null) return;
    await _run(() => onOutcome(m, status), 'Meeting marked ${status.toLowerCase()}.');
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.investigation;
    final primary = GuidanceTabColors.primaryText(context);
    final secondary = GuidanceTabColors.secondaryText(context);
    final canEdit = inv.isOpen;

    Widget chip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: GoogleFonts.poppins(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        );

    return BentoCard(
      backgroundColor: GuidanceTabColors.card(context),
      borderColor: GuidanceTabColors.cardBorder(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.studentName,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primary)),
                    Text('${inv.studentNumber} · ${inv.section}',
                        style: GoogleFonts.poppins(fontSize: 12, color: secondary)),
                  ],
                ),
              ),
              chip(inv.isOpen ? 'Open' : 'Complete',
                  inv.isOpen ? const Color(0xFFE0A100) : const Color(0xFF2E9E6A)),
            ],
          ),
          const SizedBox(height: 12),
          Text(inv.offenseLabel,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
          if (inv.incidentAt != null)
            Text('Incident: ${_formatDateTime(inv.incidentAt!)}',
                style: GoogleFonts.poppins(fontSize: 11.5, color: secondary)),
          if (inv.incidentNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(inv.incidentNotes,
                style: GoogleFonts.poppins(fontSize: 12.5, color: primary)),
          ],
          if (inv.evidencePaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Photo evidence (${inv.evidencePaths.length})',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in inv.evidencePaths) _Thumb(url: _urls[p]),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text('Meetings',
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
          const SizedBox(height: 6),
          if (inv.meetings.isEmpty)
            Text('No meeting scheduled yet.',
                style: GoogleFonts.poppins(fontSize: 12, color: secondary)),
          for (final m in inv.meetings)
            _MeetingRow(
              meeting: m,
              canEdit: canEdit && widget.view.onSetMeetingOutcome != null,
              onOutcome: (s) => _outcome(m, s),
            ),
          if (!inv.isOpen && (inv.findings ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Findings',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
            const SizedBox(height: 4),
            Text(inv.findings!,
                style: GoogleFonts.poppins(fontSize: 12.5, color: primary)),
            if ((inv.recommendation ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Recommendation: ${inv.recommendation}',
                  style: GoogleFonts.poppins(fontSize: 12, color: secondary)),
            ],
          ],
          if (canEdit) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                if (widget.view.onSchedule != null && inv.needsMeeting)
                  OutlinedButton.icon(
                    key: Key('schedule-meeting-${inv.id}'),
                    onPressed: _busy ? null : _schedule,
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text(inv.meetings.isEmpty
                        ? 'Schedule meeting'
                        : 'Reschedule meeting'),
                  ),
                if (widget.view.onComplete != null)
                  FilledButton.icon(
                    key: Key('complete-investigation-${inv.id}'),
                    onPressed: _busy ? null : _complete,
                    style: FilledButton.styleFrom(
                        backgroundColor: GuidanceTabColors.primaryAction),
                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text('Complete investigation'),
                  ),
              ],
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

  Color _color() => switch (meeting.status) {
        'Confirmed' || 'Completed' => const Color(0xFF2E9E6A),
        'Declined' || 'Missed' || 'Cancelled' => const Color(0xFFCD4855),
        'Reschedule_Requested' => const Color(0xFFE0A100),
        _ => const Color(0xFF64748B),
      };

  @override
  Widget build(BuildContext context) {
    final primary = GuidanceTabColors.primaryText(context);
    final secondary = GuidanceTabColors.secondaryText(context);
    final color = _color();
    final note = (meeting.responseNote ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: GuidanceTabColors.surfaceBackground(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatDateTime(meeting.scheduledAt)}'
                  '${meeting.location == null ? '' : ' · ${meeting.location}'}',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w500, color: primary),
                ),
                Text('Invited: ${meeting.inviteeLabel}',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: secondary)),
                if (note.isNotEmpty)
                  Text('Reply: $note',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: secondary)),
              ],
            ),
          ),
          Container(
            key: Key('meeting-status-${meeting.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              meeting.statusLabel,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          if (canEdit && !meeting.isFinished)
            PopupMenuButton<String>(
              key: Key('meeting-menu-${meeting.id}'),
              tooltip: 'Meeting outcome',
              onSelected: onOutcome,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Completed', child: Text('Mark completed')),
                PopupMenuItem(value: 'Missed', child: Text('Mark missed')),
                PopupMenuItem(value: 'Cancelled', child: Text('Cancel meeting')),
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
    final placeholder = Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GuidanceTabColors.surfaceBackground(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_outlined,
          color: GuidanceTabColors.mutedIcon(context)),
    );
    final link = url;
    if (link == null) return placeholder;
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) =>
            Dialog(child: InteractiveViewer(child: Image.network(link))),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(link,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year} $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// What the schedule dialog hands back.
class MeetingFormResult {
  const MeetingFormResult({
    required this.scheduledAt,
    required this.invitee,
    this.location,
  });

  final DateTime scheduledAt;

  /// `student`, `parent` or `both`.
  final String invitee;
  final String? location;
}

/// Pick when, where and who to invite. Defaults to tomorrow 9:00 AM with both
/// student and parent invited.
class ScheduleMeetingDialog extends StatefulWidget {
  const ScheduleMeetingDialog({super.key});

  @override
  State<ScheduleMeetingDialog> createState() => _ScheduleMeetingDialogState();
}

class _ScheduleMeetingDialogState extends State<ScheduleMeetingDialog> {
  late DateTime _when = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 9);
  }();
  final _location = TextEditingController();
  String _invitee = 'both';

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(now) ? now : _when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked == null || !mounted) return;
    setState(() => _when =
        DateTime(picked.year, picked.month, picked.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked == null || !mounted) return;
    setState(() => _when =
        DateTime(_when.year, _when.month, _when.day, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final error = validateMeetingTime(_when);
    final style = appPopupFieldStyle(context);

    Widget pickerField(Key key, IconData icon, String text, VoidCallback onTap) =>
        Material(
          color: c.fieldFill,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(icon, size: 18, color: c.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: style)),
              ]),
            ),
          ),
        );

    return AppPopup(
      title: 'Schedule Meeting',
      subtitle: 'The invitee confirms or declines in their own dashboard.',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('meeting-save'),
          label: 'Send invitation',
          onPressed: error != null
              ? null
              : () => Navigator.of(context).pop(MeetingFormResult(
                    scheduledAt: _when,
                    invitee: _invitee,
                    location: _location.text.trim().isEmpty
                        ? null
                        : _location.text.trim(),
                  )),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppPopupSection('When', icon: Icons.event_outlined),
          Row(children: [
            Expanded(
              flex: 3,
              child: pickerField(const Key('meeting-date'),
                  Icons.calendar_today_outlined, _formatDate(_when), _pickDate),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: pickerField(const Key('meeting-time'),
                  Icons.schedule_rounded, _formatTime(_when), _pickTime),
            ),
          ]),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error,
                  key: const Key('meeting-time-error'),
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: AppPopupColors.danger)),
            ),
          const SizedBox(height: 14),
          AppPopupTextField(
            label: 'Where (optional)',
            fieldKey: const Key('meeting-location'),
            controller: _location,
            hint: 'e.g. Guidance Office',
          ),
          const SizedBox(height: 14),
          const AppPopupSection('Who is invited',
              icon: Icons.people_outline_rounded),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in const [
                ('student', 'Student'),
                ('parent', 'Parent'),
                ('both', 'Student & parent'),
              ])
                ChoiceChip(
                  key: Key('meeting-invitee-$value'),
                  label: Text(label),
                  selected: _invitee == value,
                  onSelected: (_) => setState(() => _invitee = value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
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
