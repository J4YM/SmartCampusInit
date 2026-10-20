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

  /// `tap_in`, `tap_out`, `class_present`, `class_late`, `class_absent` or
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

/// The Registrar's "Activity Log": every gate tap and class attendance mark,
/// newest first, narrowed by student, section, course and date.
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
  String? _sectionId;
  String? _course;

  /// Days back from today (0 = today only); null = all time.
  int? _rangeDays;

  List<ActivityLogEntry> _entries = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
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

  void _clear() {
    _search.clear();
    _sectionId = null;
    _course = null;
    _rangeDays = null;
    _load();
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _when(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year} · $h:$m '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static Color _kindColor(String kind) => switch (kind) {
        'tap_in' => const Color(0xFF2E9E6A),
        'tap_out' => const Color(0xFF345892),
        'class_late' => const Color(0xFFE0A100),
        'class_absent' => const Color(0xFFCD4855),
        'class_excused' => const Color(0xFF64748B),
        _ => const Color(0xFF2E9E6A),
      };

  @override
  Widget build(BuildContext context) {
    final primary = RegistrarColors.rowText(context);
    final muted = RegistrarColors.mutedText(context);
    final fill = RegistrarColors.background(context);
    final fieldText = GoogleFonts.poppins(fontSize: 13, color: primary);

    Widget range(String key, String label, int? days) => ChoiceChip(
          key: Key('activity-range-$key'),
          label: Text(label),
          selected: _rangeDays == days,
          onSelected: (_) {
            _rangeDays = days;
            _load();
          },
        );

    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Activity Log',
              style: dashboardCardTitleStyle(context, color: primary)),
          const SizedBox(height: 4),
          Text(
            _loading
                ? 'Loading…'
                : '${_entries.length} ${_entries.length == 1 ? 'entry' : 'entries'}'
                    ' · gate taps and class attendance, newest first',
            style: GoogleFonts.poppins(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                height: kDashboardControlHeight,
                child: TextField(
                  key: const Key('activity-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  style: fieldText,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Student name or number',
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: muted),
                    filled: true,
                    fillColor: fill,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DashboardDropdown<String?>(
                  key: const Key('activity-section'),
                  value: _sectionId,
                  fillColor: fill,
                  textStyle: fieldText,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All sections')),
                    for (final s in widget.sections)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) {
                    _sectionId = v;
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: DashboardDropdown<String?>(
                  key: const Key('activity-course'),
                  value: _course,
                  fillColor: fill,
                  textStyle: fieldText,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All courses')),
                    for (final c in widget.courses)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) {
                    _course = v;
                    _load();
                  },
                ),
              ),
              range('0', 'Today', 0),
              range('7', 'Last 7 days', 6),
              range('30', 'Last 30 days', 29),
              range('all', 'All time', null),
              TextButton(
                key: const Key('activity-clear'),
                onPressed: _clear,
                child: const Text('Clear filters'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text('Could not load the activity log: $_error',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: RegistrarColors.dangerRed)),
                  TextButton(
                    key: const Key('activity-retry'),
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No activity matches these filters',
                    style: GoogleFonts.poppins(fontSize: 13, color: muted)),
              ),
            )
          else
            for (final e in _entries)
              Container(
                key: ValueKey('activity-${e.id}'),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: RegistrarColors.cardBorder(context))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 190,
                      child: Text(_when(e.at),
                          style: GoogleFonts.poppins(fontSize: 12, color: muted)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.studentName.isEmpty ? 'Unknown student' : e.studentName,
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primary)),
                          Text(e.studentNumber,
                              style: GoogleFonts.poppins(fontSize: 11.5, color: muted)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(e.section,
                          style: GoogleFonts.poppins(fontSize: 12.5, color: primary)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kindColor(e.kind).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(e.label,
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _kindColor(e.kind))),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(e.detail ?? '',
                          style: GoogleFonts.poppins(fontSize: 12.5, color: primary)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
