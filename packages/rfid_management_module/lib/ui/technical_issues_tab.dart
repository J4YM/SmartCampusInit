import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'shared_form_widgets.dart';

class TechnicalIssueRowModel {
  const TechnicalIssueRowModel({
    required this.id,
    required this.categoryLabel,
    required this.description,
    required this.location,
    required this.reportedByLabel,
    required this.status,
    required this.statusLabel,
    required this.createdAtLabel,
  });

  final String id;
  final String categoryLabel;
  final String description;
  final String? location;
  final String reportedByLabel;

  /// Raw db value: 'open' | 'in_progress' | 'resolved'.
  final String status;
  final String statusLabel;
  final String createdAtLabel;
}

class TechnicalIssueCommentRowModel {
  const TechnicalIssueCommentRowModel({
    required this.id,
    required this.authorLabel,
    required this.message,
    required this.createdAtLabel,
  });

  final String id;
  final String authorLabel;
  final String message;
  final String createdAtLabel;
}

const _statusFilters = ['All', 'Open', 'In Progress', 'Resolved'];
const _statusOptions = ['open', 'in_progress', 'resolved'];

/// Status-specific semantic colors — not part of the shared
/// [ItTechnicianColors] palette since "in progress" (amber) has no
/// equivalent token elsewhere in this app.
Color _statusColor(String status) {
  switch (status) {
    case 'resolved':
      return ItTechnicianColors.successGreen;
    case 'in_progress':
      return const Color(0xFFF59E0B);
    default:
      return ItTechnicianColors.dangerRed;
  }
}

class TechnicalIssuesTab extends StatelessWidget {
  const TechnicalIssuesTab({
    super.key,
    required this.reports,
    required this.isLoading,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onLoadComments,
    required this.onAddComment,
    required this.onChangeStatus,
  });

  final List<TechnicalIssueRowModel> reports;
  final bool isLoading;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final Future<List<TechnicalIssueCommentRowModel>> Function(String reportId)
      onLoadComments;
  final Future<void> Function(String reportId, String message) onAddComment;
  final Future<void> Function(String reportId, String newStatus) onChangeStatus;

  void _openDetail(BuildContext context, TechnicalIssueRowModel report) {
    showDialog<void>(
      context: context,
      builder: (_) => _TicketDetailDialog(
        report: report,
        onLoadComments: onLoadComments,
        onAddComment: onAddComment,
        onChangeStatus: onChangeStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Technical Issues',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: ItTechnicianColors.rowText(context),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in _statusFilters) ...[
                  FilterPill(
                    label: label,
                    isSelected: statusFilter == label,
                    onTap: () => onStatusFilterChanged(label),
                  ),
                  if (label != _statusFilters.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()))
          else if (reports.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No technical issues match this filter.',
                  style:
                      GoogleFonts.poppins(color: ItTechnicianColors.mutedText(context)),
                ),
              ),
            )
          else
            ...reports.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TicketRow(
                    report: report, onTap: () => _openDetail(context, report)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.report, required this.onTap});

  final TechnicalIssueRowModel report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(report.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ItTechnicianColors.cardBorder(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.categoryLabel,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: ItTechnicianColors.rowText(context),
                      ),
                    ),
                    Text(
                      report.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 10 : 12,
                        color: ItTechnicianColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                report.statusLabel,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketDetailDialog extends StatefulWidget {
  const _TicketDetailDialog({
    required this.report,
    required this.onLoadComments,
    required this.onAddComment,
    required this.onChangeStatus,
  });

  final TechnicalIssueRowModel report;
  final Future<List<TechnicalIssueCommentRowModel>> Function(String reportId)
      onLoadComments;
  final Future<void> Function(String reportId, String message) onAddComment;
  final Future<void> Function(String reportId, String newStatus) onChangeStatus;

  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  List<TechnicalIssueCommentRowModel>? _comments;
  String? _loadError;
  final _replyController = TextEditingController();

  /// FormField reads `initialValue` once, in its own initState, and owns the
  /// visible selection from then on — so reverting a failed status change
  /// takes `didChange` on the field's own state, not just a setState here.
  final _statusFieldKey = GlobalKey<FormFieldState<String>>();
  late String _status = widget.report.status;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loadError = null;
    try {
      final comments = await widget.onLoadComments(widget.report.id);
      if (!mounted) return;
      setState(() => _comments = comments);
    } catch (e) {
      // Without this the dialog would sit on a permanent spinner (and throw
      // an unhandled async error) whenever the comment fetch fails — the
      // spec calls for a retry action on fetch failure here.
      if (!mounted) return;
      setState(() => _loadError = 'Could not load replies: $e');
    }
  }

  void _retryLoad() {
    setState(() => _loadError = null);
    _load();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final message = _replyController.text.trim();
    if (message.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onAddComment(widget.report.id, message);
      // Only clear once the write actually succeeded — otherwise a failed
      // save silently wipes what the user typed.
      _replyController.clear();
      await _load();
    } catch (e) {
      _showError('Could not send reply: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onStatusSelected(String value) async {
    final previous = _status;
    if (value == previous) return;
    _status = value;
    try {
      await widget.onChangeStatus(widget.report.id, value);
    } catch (e) {
      // The optimistic selection was never persisted — put the dropdown back
      // where it was rather than leaving it showing a phantom status.
      if (!mounted) return;
      _status = previous;
      _statusFieldKey.currentState?.didChange(previous);
      _showError('Could not update status: $e');
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metaStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      color: ItTechnicianColors.mutedText(context),
    );

    // Not built on the shared DialogShell — unlike this package's other two
    // dialogs (reader/student forms, which are just a scrolling stack of
    // fields), this one has an inner Expanded comment list that needs a
    // bounded-height ancestor. DialogShell's Flexible+SingleChildScrollView
    // body wrapper gives its child unbounded height instead, which breaks
    // Expanded. Same rounded-16/title+close-X/pill-action shell, built
    // directly so the fixed-height body can host the Expanded list.
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        // Bounded by the viewport (not a magic-number height) — the fixed
        // header/dropdown/reply-box rows leave a real widget test's default
        // 800×600 window with visibly less room than a hardcoded body
        // height like 460 assumed, causing a genuine bottom overflow.
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: ItTechnicianColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ItTechnicianColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.report.categoryLabel,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: ItTechnicianColors.rowText(context),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: ItTechnicianColors.rowText(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.report.description,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        color: ItTechnicianColors.rowText(context),
                      ),
                    ),
                    if (widget.report.location != null) ...[
                      const SizedBox(height: 4),
                      Text('Location: ${widget.report.location}',
                          style: metaStyle),
                    ],
                    const SizedBox(height: 4),
                    Text('Reported by ${widget.report.reportedByLabel}',
                        style: metaStyle),
                    const SizedBox(height: 14),
                    const FieldLabel('Status'),
                    DropdownButtonFormField<String>(
                      key: _statusFieldKey,
                      value: _status,
                      icon: dropdownArrowIcon(context),
                      style: fieldTextStyle(context),
                      dropdownColor: ItTechnicianColors.card(context),
                      decoration: fieldDecoration(context),
                      items: _statusOptions
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s == 'open'
                                    ? 'Open'
                                    : s == 'in_progress'
                                        ? 'In Progress'
                                        : 'Resolved'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _onStatusSelected(value);
                      },
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: _loadError != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _loadError!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: context.isMobileWidth ? 10 : 12,
                                      color: ItTechnicianColors.dangerRed,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  PillButton(label: 'Retry', onTap: _retryLoad),
                                ],
                              ),
                            )
                          : _comments == null
                              ? const Center(child: CircularProgressIndicator())
                              : _comments!.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No replies yet.',
                                        style: GoogleFonts.poppins(
                                            color:
                                                ItTechnicianColors.mutedText(context)),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _comments!.length,
                                      itemBuilder: (context, index) {
                                        final c = _comments![index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 6),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                c.authorLabel,
                                                style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: context.isMobileWidth ? 10 : 12,
                                                  color: ItTechnicianColors
                                                      .rowText(context),
                                                ),
                                              ),
                                              Text(
                                                c.message,
                                                style: GoogleFonts.poppins(
                                                  fontSize: context.isMobileWidth ? 11 : 13,
                                                  color: ItTechnicianColors
                                                      .rowText(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            style: fieldTextStyle(context),
                            decoration: fieldDecoration(context, hintText: 'Reply...'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                          color: ItTechnicianColors.azureBlue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PaleButton(
                      label: 'Close', onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
