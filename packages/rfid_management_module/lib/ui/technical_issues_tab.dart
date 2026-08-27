import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class _IssueColors {
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const dangerRed = Color(0xFFDC2626);
}

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
  final Future<List<TechnicalIssueCommentRowModel>> Function(String reportId) onLoadComments;
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
        color: _IssueColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _IssueColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Technical Issues',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: _IssueColors.primaryText),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _statusFilters.map((label) {
              return ChoiceChip(
                label: Text(label),
                selected: statusFilter == label,
                onSelected: (_) => onStatusFilterChanged(label),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator()))
          else if (reports.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No technical issues match this filter.')),
            )
          else
            ...reports.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TicketRow(report: report, onTap: () => _openDetail(context, report)),
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

  Color get _statusColor {
    switch (report.status) {
      case 'resolved':
        return const Color(0xFF16A34A);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _IssueColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.categoryLabel,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _IssueColors.primaryText),
                    ),
                    Text(
                      report.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: _IssueColors.secondaryText),
                    ),
                  ],
                ),
              ),
              Text(report.statusLabel, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor)),
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
  final Future<List<TechnicalIssueCommentRowModel>> Function(String reportId) onLoadComments;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    return AlertDialog(
      title: Text(widget.report.categoryLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.report.description),
            if (widget.report.location != null) ...[
              const SizedBox(height: 4),
              Text('Location: ${widget.report.location}', style: const TextStyle(color: _IssueColors.secondaryText)),
            ],
            const SizedBox(height: 4),
            Text('Reported by ${widget.report.reportedByLabel}', style: const TextStyle(color: _IssueColors.secondaryText)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: _statusFieldKey,
              value: _status,
              decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
              items: _statusOptions
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s == 'open' ? 'Open' : s == 'in_progress' ? 'In Progress' : 'Resolved'),
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
                            style: const TextStyle(color: _IssueColors.dangerRed),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _retryLoad, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : _comments == null
                  ? const Center(child: CircularProgressIndicator())
                  : _comments!.isEmpty
                      ? const Center(child: Text('No replies yet.'))
                      : ListView.builder(
                          itemCount: _comments!.length,
                          itemBuilder: (context, index) {
                            final c = _comments![index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.authorLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                  Text(c.message),
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
                    decoration: const InputDecoration(hintText: 'Reply...', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
