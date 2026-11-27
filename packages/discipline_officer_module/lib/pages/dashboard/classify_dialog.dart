import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import '../../util/violation_suggester.dart';
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
  BehaviorCategory? _categoryFilter;

  late final BehaviorCategory? _suggestedCategory;
  late final List<OffenseOption> _suggestedOffenses;

  @override
  void initState() {
    super.initState();
    // Suggestions come from what the reporter wrote; the officer decides.
    final text = widget.caseItem.description;
    _suggestedCategory = ViolationSuggester.suggestBehaviorCategory(text);
    _suggestedOffenses =
        ViolationSuggester.suggestOffenses(text, widget.offenseOptions);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<OffenseOption> get _visible {
    final q = _search.text.trim().toLowerCase();
    final filter = _categoryFilter?.dbValue;
    final base = filter == null
        ? widget.offenseOptions
        : widget.offenseOptions
            .where((o) => o.behaviorCategory == filter)
            .toList();
    if (q.isEmpty) return base;
    return base
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
          if (_suggestedCategory != null || _suggestedOffenses.isNotEmpty) ...[
            const SizedBox(height: 14),
            const AppPopupSection('Suggested', icon: Icons.auto_awesome_rounded),
            if (_suggestedCategory != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Category: ${_suggestedCategory.label}',
                  key: const Key('classify-suggested-category'),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.text),
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in _suggestedOffenses)
                  FilterChip(
                    key: Key('classify-suggestion-${o.id}'),
                    label: Text(o.label,
                        style: GoogleFonts.poppins(fontSize: 11.5)),
                    selected: _selected.contains(o.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selected.add(o.id);
                      } else {
                        _selected.remove(o.id);
                      }
                    }),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Suggested from the report text. Please confirm.',
                style: GoogleFonts.poppins(fontSize: 11, color: c.muted),
              ),
            ),
          ],
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
            padding: const EdgeInsets.only(top: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              children: [
                ChoiceChip(
                  label: Text('All categories',
                      style: GoogleFonts.poppins(fontSize: 11.5)),
                  selected: _categoryFilter == null,
                  onSelected: (_) => setState(() => _categoryFilter = null),
                ),
                for (final cat in BehaviorCategory.values) ...[
                  const SizedBox(width: 6),
                  ChoiceChip(
                    key: Key('classify-filter-${cat.dbValue}'),
                    label: Text(cat.label,
                        style: GoogleFonts.poppins(fontSize: 11.5)),
                    selected: _categoryFilter == cat,
                    onSelected: (_) => setState(() => _categoryFilter = cat),
                  ),
                ],
              ],
            ),
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
