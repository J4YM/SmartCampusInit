import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import 'discipline_officer_dashboard_page.dart' show OffenseOption;

/// The Discipline Officer picks the handbook offense(s) for a report the
/// reporter filed without a classification. Pops with the ticked offense ids.
class ClassifyDialog extends StatefulWidget {
  const ClassifyDialog({
    super.key,
    required this.caseItem,
    required this.offenseOptions,
  });

  final DisciplineCaseModel caseItem;
  final List<OffenseOption> offenseOptions;

  @override
  State<ClassifyDialog> createState() => _ClassifyDialogState();
}

class _ClassifyDialogState extends State<ClassifyDialog> {
  final _search = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<OffenseOption> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.offenseOptions;
    return widget.offenseOptions
        .where((o) =>
            o.label.toLowerCase().contains(q) ||
            (o.category ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final grouped = <String, List<OffenseOption>>{};
    for (final o in _visible) {
      grouped.putIfAbsent(o.category ?? 'Other', () => []).add(o);
    }
    final report = widget.caseItem;

    return AppPopup(
      title: 'Classify Report',
      subtitle: '${report.studentName} · choose the handbook violation(s)',
      width: 560,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('classify-save'),
          label: 'Classify',
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppPopupSection('What was reported',
              icon: Icons.description_outlined),
          Text(
            report.description.isEmpty ? 'No description.' : report.description,
            style: GoogleFonts.poppins(fontSize: 12.5, color: c.text),
          ),
          const SizedBox(height: 14),
          const AppPopupSection('Violation(s)', icon: Icons.gavel_rounded),
          TextField(
            key: const Key('classify-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: appPopupFieldStyle(context),
            cursorColor: AppPopupColors.accent,
            decoration: appPopupInputDecoration(
              context,
              hint: 'Search violations',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: c.muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              '${_selected.length} selected',
              style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted),
            ),
          ),
          SizedBox(
            height: 260,
            child: grouped.isEmpty
                ? Center(
                    child: Text(
                      'No violations match your search.',
                      style:
                          GoogleFonts.poppins(fontSize: 12.5, color: c.muted),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: FilterLabelBand(
                            label: entry.key.replaceAll('_', ' '),
                            surface: c.card,
                          ),
                        ),
                        for (final o in entry.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: AppPopupCheckboxTile(
                              title: o.label,
                              value: _selected.contains(o.id),
                              onChanged: (v) => setState(() {
                                if (v) {
                                  _selected.add(o.id);
                                } else {
                                  _selected.remove(o.id);
                                }
                              }),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
