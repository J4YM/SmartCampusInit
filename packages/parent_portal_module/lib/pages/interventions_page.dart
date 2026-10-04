import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/intervention_models.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import '../widgets/folder_tabs.dart';
import '../widgets/intervention_detail_sheet.dart';
import '../widgets/parent_overview_widgets.dart' show InterventionTile;

/// The tabs of [InterventionsPage].
enum InterventionFilter { all, actionNeeded, unread, read }

/// Every intervention message — reached from the dashboard card's
/// "View all", laid out like the full Violations & Offenses page (folder
/// tabs over a list). Tapping a message marks it read and opens its detail
/// popup.
class InterventionsPage extends StatefulWidget {
  const InterventionsPage({
    super.key,
    required this.messages,
    this.onRead,
    this.initialFilter = InterventionFilter.all,
  });

  final List<InterventionMessageModel> messages;

  /// The tab selected on open — e.g. Unread when the dashboard's "unread
  /// messages" banner was tapped.
  final InterventionFilter initialFilter;

  /// Called with a message id when the parent opens it, so the dashboard
  /// (and the database) can record it as read.
  final void Function(String id)? onRead;

  @override
  State<InterventionsPage> createState() => _InterventionsPageState();
}

class _InterventionsPageState extends State<InterventionsPage> {
  late InterventionFilter _filter = widget.initialFilter;
  late List<InterventionMessageModel> _messages = [...widget.messages]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static bool _matches(InterventionFilter f, InterventionMessageModel m) =>
      switch (f) {
        InterventionFilter.all => true,
        InterventionFilter.unread => !m.isRead,
        InterventionFilter.actionNeeded => m.actionRequired,
        InterventionFilter.read => m.isRead,
      };

  static String _label(InterventionFilter f) => switch (f) {
        InterventionFilter.all => 'All',
        InterventionFilter.unread => 'Unread',
        InterventionFilter.actionNeeded => 'Action needed',
        InterventionFilter.read => 'Read',
      };

  int _countFor(InterventionFilter f) =>
      _messages.where((m) => _matches(f, m)).length;

  void _open(InterventionMessageModel m) {
    if (!m.isRead) {
      setState(() {
        _messages = [
          for (final x in _messages)
            x.id == m.id ? x.copyWith(isRead: true) : x,
        ];
      });
      widget.onRead?.call(m.id);
    }
    showInterventionDetailSheet(context, m, isDarkMode: context.isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _messages.where((m) => _matches(_filter, m)).toList();

    return Scaffold(
      backgroundColor: ParentPortalColors.pageBackground(context),
      appBar: AppBar(
        backgroundColor: ParentPortalColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ParentPortalColors.textPrimary(context),
        title: Text(
          'Interventions',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DashboardPageWrapper(
          maxWidth: ParentPortalSpacing.maxContentWidth,
          padding: EdgeInsets.symmetric(
            horizontal: ParentPortalSpacing.pageHorizontal(context),
            vertical: ParentPortalSpacing.lg,
          ),
          child: FolderTabbedPanel(
            tabs: [
              for (final f in InterventionFilter.values)
                FolderTabSpec(_label(f), _countFor(f)),
            ],
            selectedIndex: InterventionFilter.values.indexOf(_filter),
            onSelected: (i) =>
                setState(() => _filter = InterventionFilter.values[i]),
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 34,
                          color: ParentPortalColors.textMuted(context),
                        ),
                        const SizedBox(height: ParentPortalSpacing.sm),
                        Text(
                          'No messages match this filter.',
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: ParentPortalColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      for (final m in filtered)
                        InterventionTile(message: m, onTap: () => _open(m)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
