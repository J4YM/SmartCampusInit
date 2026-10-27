import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'class_schedule_view.dart' show SectionOption;

/// One row of the attendance activity log: a gate tap or a class attendance
/// mark, for one student.
class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.label,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    this.detail,
  });

  final String id;
  final DateTime at;

  /// `tap_in`, `tap_out`, `did_not_tap_out`, `class_present`, `class_late`,
  /// `class_absent` or
  /// `class_excused`; only used to colour the row.
  final String kind;

  /// "Tapped in", "Class: Late", …
  final String label;
  final String studentName;
  final String studentNumber;
  final String section;

  /// The reader's location for a tap, the subject for a class mark.
  final String? detail;
}

/// Loads the log for the chosen filters (every filter optional).
typedef ActivityLoader = Future<List<ActivityLogEntry>> Function({
  String? studentQuery,
  String? sectionId,
  String? course,
  DateTime? from,
  DateTime? to,
});

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('When', flex: 3, minWidth: 190),
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Section', flex: 2, minWidth: 130),
  DashboardTableColumn('Activity', flex: 3, minWidth: 170),
  DashboardTableColumn('Details', flex: 4, minWidth: 200),
];

/// The Registrar's "Activity Log": every gate tap and class attendance mark,
/// newest first, narrowed by student, section, course and date — a table card
/// with search and the shared Filter popup, like every other Registrar tab.
class AttendanceActivityView extends StatefulWidget {
  const AttendanceActivityView({
    super.key,
    required this.sections,
    required this.courses,
    required this.onLoad,
  });

  final List<SectionOption> sections;
  final List<String> courses;
  final ActivityLoader onLoad;

  @override
  State<AttendanceActivityView> createState() => _AttendanceActivityViewState();
}

class _AttendanceActivityViewState extends State<AttendanceActivityView> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String? _sectionId;
  String? _course;

  /// Days back from today (0 = today only); null = all time.
  int? _rangeDays;

  List<ActivityLogEntry> _entries = const [];
  bool _loading = true;
  Object? _error;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
    });
    final today = DateTime.now();
    final days = _rangeDays;
    final query = _search.text.trim();
    try {
      final entries = await widget.onLoad(
        studentQuery: query.isEmpty ? null : query,
        sectionId: _sectionId,
        course: _course,
        from: days == null
            ? null
            : DateTime(today.year, today.month, today.day - days),
        to: days == null ? null : DateTime(today.year, today.month, today.day),
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Typing reloads once the person pauses (the log is filtered on the server).
  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _load);
  }

  static Color _kindColor(String kind) => switch (kind) {
        'tap_in' => const Color(0xFF2E9E6A),
        'tap_out' => const Color(0xFF345892),
        'did_not_tap_out' => const Color(0xFFD97706),
        'class_late' => const Color(0xFFD97706),
        'class_absent' => const Color(0xFFCD4855),
        'class_excused' => const Color(0xFF64748B),
        _ => const Color(0xFF2E9E6A),
      };

  /// The date-range facet's value for the current selection.
  String? get _rangeValue => _rangeDays?.toString();

  @override
  Widget build(BuildContext context) {
    final pageSize = context.cardPageSize;
    final totalPages =
        _entries.isEmpty ? 1 : (_entries.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageItems =
        _entries.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _ActivityRow(
          key: ValueKey('activity-${pageItems[i].id}'),
          entry: pageItems[i],
          color: _kindColor(pageItems[i].kind),
          showDivider: i < pageItems.length - 1,
        ),
    ];

    final Widget empty;
    if (_error != null) {
      empty = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load the activity log: $_error',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: RegistrarColors.dangerRed),
            ),
            const SizedBox(height: 12),
            SecondaryPillButton(
              key: const Key('activity-retry'),
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: _load,
            ),
          ],
        ),
      );
    } else if (_loading) {
      empty = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      empty = const DashboardTableEmptyState(
        icon: Icons.fact_check_outlined,
        message: 'No activity matches these filters',
      );
    }

    return TitledTableCard(
      title: 'Activity Log',
      subtitle: Text(
        _loading
            ? 'Loading…'
            : '${_entries.length} ${_entries.length == 1 ? 'entry' : 'entries'}'
                ' | gate taps and class attendance, newest first',
        style: TitledTableCard.subtitleStyle(context,
            color: RegistrarColors.mutedText(context)),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: DashboardSearchField(
              key: const Key('activity-search'),
              controller: _search,
              hint: 'Search student name or number',
              fillColor: RegistrarColors.background(context),
              textColor: RegistrarColors.rowText(context),
              hintColor: RegistrarColors.placeholderText(context),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(width: 10),
          FilterMenuButton(
            key: const Key('activity-filter'),
            backgroundColor: RegistrarColors.background(context),
            menuColor: RegistrarColors.card(context),
            borderColor: RegistrarColors.cardBorder(context),
            iconColor: RegistrarColors.placeholderText(context),
            textColor: RegistrarColors.rowText(context),
            mutedTextColor: RegistrarColors.mutedText(context),
            accentColor: RegistrarColors.azureBlue,
            sections: [
              FilterMenuSection(
                title: 'Date',
                options: const [
                  FilterMenuOption(label: 'Today', value: '0'),
                  FilterMenuOption(label: 'Last 7 days', value: '6'),
                  FilterMenuOption(label: 'Last 30 days', value: '29'),
                ],
                selectedValue: _rangeValue,
                onChanged: (value) {
                  _rangeDays = value == null ? null : int.parse(value);
                  _load();
                },
              ),
              if (widget.courses.isNotEmpty)
                FilterMenuSection(
                  title: 'Course',
                  options: [
                    for (final c in widget.courses)
                      FilterMenuOption(label: c, value: c),
                  ],
                  selectedValue: _course,
                  onChanged: (value) {
                    _course = value;
                    _load();
                  },
                ),
            ],
            sectionFilter: FilterSectionPicker(
              entries: [
                for (final s in widget.sections)
                  PickerEntry.section(
                    id: s.id,
                    name: s.name,
                    program: s.program,
                    yearLevel: s.yearLevel,
                  ),
              ],
              selectedId: _sectionId,
              onChanged: (id) {
                _sectionId = id;
                _load();
              },
            ),
          ),
        ],
      ),
      columns: _columns,
      rows: _loading || _error != null ? const [] : rows,
      empty: empty,
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      titleColor: RegistrarColors.rowText(context),
      footer: _loading || _error != null || _entries.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: _entries.length,
              textColor: RegistrarColors.mutedText(context),
              accentColor: RegistrarColors.azureBlue,
              mutedBackground: RegistrarColors.background(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    super.key,
    required this.entry,
    required this.color,
    required this.showDivider,
  });

  final ActivityLogEntry entry;
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    return DashboardTableRow(
      columns: _columns,
      showDivider: showDivider,
      cells: [
        line(formatDateTime12h(e.at), dashboardTableMetaStyle(context)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(e.studentName.isEmpty ? 'Unknown student' : e.studentName,
                dashboardTablePrimaryStyle(context)),
            line(e.studentNumber, dashboardTableSubStyle(context)),
          ],
        ),
        line(e.section, dashboardTableBodyStyle(context)),
        Align(
          alignment: Alignment.centerLeft,
          // The same soft pill the Escalation / Referral badges use.
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              e.label,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ),
        line(e.detail ?? '', dashboardTableBodyStyle(context)),
      ],
    );
  }
}
