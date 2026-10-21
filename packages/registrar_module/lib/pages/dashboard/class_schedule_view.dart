import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'registrar_dashboard_page.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class ScheduleEntryModel {
  const ScheduleEntryModel({
    required this.id,
    required this.subject,
    required this.gradeSection,
    required this.teacher,
    required this.room,
    required this.days,
    required this.timeRange,
    this.subjectId,
    this.sectionId,
    this.professorId,
    this.schoolYear,
    this.term,
    this.startTime,
    this.endTime,
    this.hasMeetings = false,
  });

  final String id;
  final String subject;
  final String gradeSection;
  final String teacher;
  final String room;
  final List<String> days;
  final String timeRange;

  /// The raw values behind the row, so "Edit" can prefill the form. Null for
  /// demo data, which can't be edited.
  final String? subjectId;
  final String? sectionId;
  final String? professorId;
  final String? schoolYear;
  final String? term;

  /// 24-hour "HH:mm".
  final String? startTime;
  final String? endTime;

  /// True when the row's room/days/time come from imported
  /// `class_section_meetings` (possibly several lecture/lab slots) rather
  /// than the single schedule the manual form writes. Saving an edit
  /// replaces those with one meeting per selected day.
  final bool hasMeetings;

  factory ScheduleEntryModel.fromJson(Map<String, dynamic> json) {
    return ScheduleEntryModel(
      id: json['id'] as String,
      subject: json['subject'] as String,
      gradeSection: json['grade_section'] as String? ?? '',
      teacher: json['teacher'] as String? ?? '',
      room: json['room'] as String? ?? '',
      days: (json['days'] as List<dynamic>?)?.cast<String>() ?? const [],
      timeRange: json['time_range'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'grade_section': gradeSection,
      'teacher': teacher,
      'room': room,
      'days': days,
      'time_range': timeRange,
    };
  }
}

/// A subject a class-schedule offering can be created for. Backed by the
/// real `subjects` table via `RegistrarRepository.fetchSubjects()`.
class SubjectOption {
  const SubjectOption(
      {required this.id, required this.code, required this.title});

  final String id;
  final String code;
  final String title;

  String get label => '$code — $title';
}

/// A teacher (profile with role `Teacher`) a class-schedule offering can be
/// assigned to. Backed by the real `profiles` table via
/// `RegistrarRepository.fetchTeachers()`.
class TeacherOption {
  const TeacherOption({required this.id, required this.fullName});

  final String id;
  final String fullName;
}

/// A section a class-schedule offering can be assigned to. Backed by the
/// real `sections` table via `RegistrarRepository.fetchSections()`.
class SectionOption {
  const SectionOption({
    required this.id,
    required this.name,
    required this.yearLevel,
    this.program,
  });

  final String id;
  final String name; // e.g. "BSIT-3B"
  final int yearLevel; // e.g. 3

  /// `sections.program` (e.g. "BSIT") — null for an older row saved
  /// before that column had a value. Used as the batch-enrollment
  /// import's fallback `course` when a row's own "Program" cell is blank.
  final String? program;
}

/// Called with the assembled "Add Class Schedule" form values when "Save
/// Changes" is tapped.
typedef ClassScheduleSaveCallback = void Function({
  required String subjectId,
  required String professorId,
  required String sectionId,
  required String schoolYear,
  required String term,
  required String room,
  required List<String> days,
  required String startTime,
  required String endTime,
});

/// Runs a picked Excel file (Classes+Professor list, Confirmation of
/// Faculty Loading, or Room Schedule export) through the schedule import
/// pipeline, tagged with whatever School Year/Term the form currently holds.
typedef ClassScheduleImportCallback = Future<void> Function({
  required Uint8List bytes,
  required String schoolYear,
  required String term,
});

// ---------------------------------------------------------------------------
// Class Schedule tab — schedule table. The "Add Class Schedule" form lives
// in [showAddClassScheduleDialog], opened from the Generated Class Schedule
// card's header.
// ---------------------------------------------------------------------------

class ClassScheduleView extends StatefulWidget {
  const ClassScheduleView({
    super.key,
    required this.entries,
    this.onEnrollSection,
    this.onEdit,
    this.onDelete,
  });

  final List<ScheduleEntryModel> entries;

  /// Row actions. The pencil / trash buttons are hidden when omitted (demo
  /// data has nothing real to change).
  final ValueChanged<ScheduleEntryModel>? onEdit;
  final ValueChanged<ScheduleEntryModel>? onDelete;

  /// Called with a row's `class_sections.id` when its "Enroll this
  /// section's students" button is tapped. Falls back to a disabled button
  /// when omitted (demo behavior).
  final ValueChanged<String>? onEnrollSection;

  @override
  State<ClassScheduleView> createState() => _ClassScheduleViewState();
}

class _ClassScheduleViewState extends State<ClassScheduleView> {
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final e in widget.entries)
        if (matchesSearchQuery(_query, [
          e.subject,
          e.gradeSection,
          e.teacher,
          e.room,
          e.timeRange,
          ...e.days,
        ]))
          e,
    ];
    final totalPages =
        entries.isEmpty ? 1 : (entries.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageEntries =
        entries.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  'Class Schedules',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
                );
                final search = SearchField(
                  controller: _searchController,
                  hintText: 'Search schedules',
                  onChanged: (value) => setState(() {
                    _query = value;
                    _currentPage = 1;
                  }),
                );
                // Narrow card: the search drops under the title instead of
                // being squeezed beside it.
                if (context.isMobileWidth || constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 12),
                      MaxWidthAligned(child: search),
                    ],
                  );
                }
                return Row(
                  children: [
                    title,
                    const SizedBox(width: 16),
                    Expanded(
                      child: MaxWidthAligned(
                        alignment: Alignment.centerRight,
                        child: search,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          DashboardTableSection(
            columns: _scheduleColumns,
            body: DashboardTableRows(
              empty: DashboardTableEmptyState(
                icon: Icons.calendar_month_outlined,
                message: widget.entries.isEmpty
                    ? 'No class schedules yet'
                    : 'No class schedules match your search',
              ),
              rows: [
                for (var i = 0; i < pageEntries.length; i++)
                  _ScheduleRow(
                    key: ValueKey('schedule-${pageEntries[i].id}'),
                    entry: pageEntries[i],
                    showDivider: i < pageEntries.length - 1,
                    onEnrollSection: widget.onEnrollSection,
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                  ),
              ],
            ),
          ),
          if (entries.isNotEmpty)
            DashboardTableFooter(
              child: CardPaginationFooter(
                currentPage: currentPage,
                totalPages: totalPages,
                totalCount: entries.length,
                textColor: RegistrarColors.mutedText(context),
                accentColor: RegistrarColors.azureBlue,
                mutedBackground: RegistrarColors.background(context),
                onPrevious: () =>
                    setState(() => _currentPage = currentPage - 1),
                onNext: () => setState(() => _currentPage = currentPage + 1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the "Add Class Schedule" form as a dialog (desktop) / bottom sheet
/// (mobile). [context] must sit below the dashboard's own self-built Theme —
/// the route renders on the root overlay, so that Theme is captured here and
/// re-applied, otherwise the form always shows light-mode.
Future<void> showAddClassScheduleDialog(
  BuildContext context, {
  required List<SubjectOption> subjectOptions,
  required List<TeacherOption> teacherOptions,
  required List<SectionOption> sectionOptions,
  List<String> roomOptions = const [],
  ClassScheduleSaveCallback? onSaveChanges,
  ClassScheduleImportCallback? onImportSchedule,
  bool hasExistingSchedules = false,
  ScheduleEntryModel? editing,
  bool showImport = true,
}) {
  final theme = Theme.of(context);
  return showResponsiveSheet<void>(
    context: context,
    backgroundColor: RegistrarColors.card(context),
    handleColor: RegistrarColors.cardBorder(context),
    desktopMaxWidth: 760,
    builder: (sheetContext) => Theme(
      data: theme,
      child: _AddClassScheduleForm(
        subjectOptions: subjectOptions,
        teacherOptions: teacherOptions,
        sectionOptions: sectionOptions,
        roomOptions: roomOptions,
        onSaveChanges: onSaveChanges,
        onImportSchedule: onImportSchedule,
        hasExistingSchedules: hasExistingSchedules,
        editing: editing,
        showImport: showImport,
      ),
    ),
  );
}

class _AddClassScheduleForm extends StatefulWidget {
  const _AddClassScheduleForm({
    required this.subjectOptions,
    required this.teacherOptions,
    required this.sectionOptions,
    this.roomOptions = const [],
    this.onSaveChanges,
    this.onImportSchedule,
    this.hasExistingSchedules = false,
    this.editing,
    this.showImport = true,
  });

  /// When set, the form edits this existing schedule: prefilled, titled
  /// "Edit Class Schedule", and without the import button.
  final ScheduleEntryModel? editing;

  /// False hides the "Upload spreadsheet" button (the Scheduling Officer has
  /// its own Faculty Loading upload card instead).
  final bool showImport;

  /// True when class schedules are already on file: importing a file then
  /// asks for confirmation first, since it replaces professor/course
  /// assignments of matching offerings.
  final bool hasExistingSchedules;

  final List<SubjectOption> subjectOptions;
  final List<TeacherOption> teacherOptions;
  final List<SectionOption> sectionOptions;

  /// Room numbers from the `rooms` table. When empty (demo data, or the
  /// table couldn't be read) the Room field falls back to free text.
  final List<String> roomOptions;
  final ClassScheduleSaveCallback? onSaveChanges;

  /// Falls back to a confirmation snackbar via [UploadSpreadsheetButton]'s
  /// own default when omitted (demo behavior).
  final ClassScheduleImportCallback? onImportSchedule;

  @override
  State<_AddClassScheduleForm> createState() => _AddClassScheduleFormState();
}

class _AddClassScheduleFormState extends State<_AddClassScheduleForm> {
  String _educationLevel = 'College';
  final Set<String> _selectedDays = {'Mon', 'Thu', 'Fri'};

  String? _selectedSubjectId;
  String? _selectedProfessorId;
  String? _selectedSectionId;
  late final TextEditingController _roomController;
  late final TextEditingController _schoolYearController;
  String? _selectedRoom;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _term = '1st Semester';
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _roomController = TextEditingController();
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    _schoolYearController =
        TextEditingController(text: '$startYear-${startYear + 1}');

    final e = widget.editing;
    if (e != null) {
      _selectedSubjectId = e.subjectId;
      _selectedProfessorId = e.professorId;
      // A dropdown value that isn't among its items is an assertion error.
      if (widget.sectionOptions.any((s) => s.id == e.sectionId)) {
        _selectedSectionId = e.sectionId;
      }
      if (e.schoolYear != null && e.schoolYear!.isNotEmpty) {
        _schoolYearController.text = e.schoolYear!;
      }
      if (e.term == '1st Semester' || e.term == '2nd Semester') {
        _term = e.term!;
      }
      _selectedDays
        ..clear()
        ..addAll(e.days);
      _roomController.text = e.room;
      _selectedRoom = e.room.isEmpty ? null : e.room;
      _startTime = _parseHhmm(e.startTime);
      _endTime = _parseHhmm(e.endTime);
    }
  }

  static TimeOfDay? _parseHhmm(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return (h == null || m == null) ? null : TimeOfDay(hour: h, minute: m);
  }

  /// The Room dropdown's choices, plus the schedule's current room when it
  /// isn't one of them (e.g. several rooms joined from imported meetings), so
  /// the dropdown can still show it.
  List<String> get _roomChoices {
    final current = _selectedRoom;
    return [
      ...widget.roomOptions,
      if (current != null && !widget.roomOptions.contains(current)) current,
    ];
  }

  @override
  void dispose() {
    _roomController.dispose();
    _schoolYearController.dispose();
    super.dispose();
  }

  void _handleSaveChanges() {
    final subjectId = _selectedSubjectId;
    final professorId = _selectedProfessorId;
    final sectionId = _selectedSectionId;
    final schoolYear = _schoolYearController.text.trim();
    final room = (widget.roomOptions.isEmpty
            ? _roomController.text
            : _selectedRoom ?? '')
        .trim();
    final startTime = _startTime;
    final endTime = _endTime;
    if (subjectId == null ||
        professorId == null ||
        sectionId == null ||
        schoolYear.isEmpty ||
        room.isEmpty ||
        startTime == null ||
        endTime == null ||
        _selectedDays.isEmpty) {
      setState(() => _error = 'Fill in Subject, Section, Teacher, Room, '
          'Start/End Time, School Year, and at least one day.');
      return;
    }
    if (_minutes(endTime) <= _minutes(startTime)) {
      setState(() => _error = 'End Time must be after Start Time.');
      return;
    }
    Navigator.of(context).pop();
    widget.onSaveChanges?.call(
      subjectId: subjectId,
      professorId: professorId,
      sectionId: sectionId,
      schoolYear: schoolYear,
      term: _term,
      room: room,
      days: _selectedDays.toList(),
      startTime: _hhmm(startTime),
      endTime: _hhmm(endTime),
    );
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// 24-hour "HH:mm" — what the `class_sections` `time` columns store.
  static String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Future<void> _handleImportFile(PlatformFile file) async {
    final onImportSchedule = widget.onImportSchedule;
    final bytes = file.bytes;
    if (onImportSchedule == null || bytes == null || _importing) return;
    final schoolYear = _schoolYearController.text.trim();
    if (schoolYear.isEmpty) {
      setState(() => _error = 'Enter a School Year before importing a file.');
      return;
    }
    if (widget.hasExistingSchedules) {
      final proceed = await _confirmOverwrite(file.name);
      if (proceed != true || !mounted) return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      await onImportSchedule(bytes: bytes, schoolYear: schoolYear, term: _term);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    // The host reports the import result itself (snackbar); close so the
    // refreshed schedule table is visible behind it.
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool?> _confirmOverwrite(String fileName) {
    return showAppPopup<bool>(
      context: context,
      builder: (dialogContext) => AppPopup(
        title: 'Overwrite existing schedules?',
        width: 460,
        body: Text(
          'Class schedules are already on file. Importing "$fileName" will '
          'overwrite the professor and course assignments of any matching '
          'offerings, and add the rest. This cannot be undone.',
        ),
        actions: [
          AppPopupSecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppPopupPrimaryButton(
            label: 'Overwrite',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
  }

  SectionOption? get _selectedSection {
    for (final option in widget.sectionOptions) {
      if (option.id == _selectedSectionId) return option;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = _selectedSection;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        context.isMobileWidth ? 8 : 20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPopupHeader(
            title: widget.editing == null
                ? 'Add Class Schedule'
                : 'Edit Class Schedule',
            onClose: () => Navigator.of(context).pop(),
          ),
          if (widget.editing?.hasMeetings ?? false) ...[
            const SizedBox(height: 8),
            Text(
              'This schedule was imported from a file and may have several '
              'lecture/lab meetings. Saving replaces them with one meeting '
              'per selected day at the room and time below.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: RegistrarColors.mutedText(context),
              ),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            const gap = 16.0;
            final width = constraints.maxWidth;
            final wide = width >= 560;
            final big = wide ? (width - gap) / 2 : width;
            final small = wide ? (width - 2 * gap) / 3 : (width - gap) / 2;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: big,
                      child: _NotYetWiredField(
                        child: _EducationLevelField(
                          value: _educationLevel,
                          onChanged: (v) => setState(() => _educationLevel = v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: big,
                      child: _SearchableSelectField(
                        label: 'Subject',
                        placeholder: 'Search subject',
                        options: [
                          for (final o in widget.subjectOptions)
                            (id: o.id, label: o.label),
                        ],
                        selectedId: _selectedSubjectId,
                        onChanged: (v) =>
                            setState(() => _selectedSubjectId = v),
                      ),
                    ),
                    SizedBox(
                      width: big,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionDropdown(
                            options: widget.sectionOptions,
                            selectedId: _selectedSectionId,
                            onChanged: (v) =>
                                setState(() => _selectedSectionId = v),
                          ),
                          if (selectedSection != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Year ${selectedSection.yearLevel}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: RegistrarColors.mutedText(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: big,
                      child: _SearchableSelectField(
                        label: 'Teacher',
                        placeholder: 'Search teacher',
                        options: [
                          for (final o in widget.teacherOptions)
                            (id: o.id, label: o.fullName),
                        ],
                        selectedId: _selectedProfessorId,
                        onChanged: (v) =>
                            setState(() => _selectedProfessorId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Education Level isn\'t wired to a real section yet — every '
                  'class section is College-level regardless of this field. '
                  'Subject, Teacher, and Section above are real.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: small,
                      child: widget.roomOptions.isEmpty
                          ? _LabeledTextField(
                              label: 'Room',
                              controller: _roomController,
                            )
                          : AppPopupDropdown<String>(
                              label: 'Room',
                              value: _selectedRoom,
                              hint: 'Select room',
                              items: [
                                for (final room in _roomChoices)
                                  DropdownMenuItem(
                                    value: room,
                                    child: Text(room,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedRoom = v),
                            ),
                    ),
                    SizedBox(
                      width: small,
                      child: _TimePickerField(
                        label: 'Start Time',
                        value: _startTime,
                        initialTime: const TimeOfDay(hour: 8, minute: 0),
                        onChanged: (t) => setState(() => _startTime = t),
                      ),
                    ),
                    SizedBox(
                      width: small,
                      child: _TimePickerField(
                        label: 'End Time',
                        value: _endTime,
                        initialTime: _startTime == null
                            ? const TimeOfDay(hour: 9, minute: 30)
                            : _startTime!
                                .replacing(hour: (_startTime!.hour + 1) % 24),
                        onChanged: (t) => setState(() => _endTime = t),
                      ),
                    ),
                    SizedBox(
                      width: small,
                      child: _LabeledTextField(
                        label: 'School Year',
                        controller: _schoolYearController,
                      ),
                    ),
                    SizedBox(
                      width: small,
                      child: _TermDropdown(
                        value: _term,
                        onChanged: (v) {
                          if (v != null) setState(() => _term = v);
                        },
                      ),
                    ),
                    _LabeledMultiPillGroup(
                      label: 'Days',
                      options: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
                      selected: _selectedDays,
                      onToggled: (day) => setState(() {
                        _selectedDays.contains(day)
                            ? _selectedDays.remove(day)
                            : _selectedDays.add(day);
                      }),
                    ),
                  ],
                ),
              ],
            );
          }),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kDangerTextColor,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (widget.editing != null || !widget.showImport)
                const SizedBox.shrink()
              else if (_importing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                UploadSpreadsheetButton(
                  onFileSelected: _handleImportFile,
                  accentColor: RegistrarColors.azureBlue,
                  backgroundColor: RegistrarColors.background(context),
                ),
              const Spacer(),
              SaveChangesButton(onTap: _handleSaveChanges),
            ],
          ),
        ],
      ),
    );
  }
}

const _scheduleColumns = <DashboardTableColumn>[
  DashboardTableColumn('Subject', flex: 3, minWidth: 220),
  DashboardTableColumn('Grade & Section', flex: 2, minWidth: 150),
  DashboardTableColumn('Teacher', flex: 2, minWidth: 180),
  DashboardTableColumn('Room', flex: 1, minWidth: 110),
  DashboardTableColumn('Days', flex: 2, minWidth: 210),
  DashboardTableColumn('Time', flex: 2, minWidth: 170),
  DashboardTableColumn('Actions', flex: 1, minWidth: 140, sticky: true),
];

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    super.key,
    required this.entry,
    required this.showDivider,
    this.onEnrollSection,
    this.onEdit,
    this.onDelete,
  });

  final ScheduleEntryModel entry;
  final bool showDivider;
  final ValueChanged<String>? onEnrollSection;
  final ValueChanged<ScheduleEntryModel>? onEdit;
  final ValueChanged<ScheduleEntryModel>? onDelete;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _scheduleColumns,
      showDivider: showDivider,
      cells: [
        Text(
          entry.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTablePrimaryStyle(context),
        ),
        Text(
          entry.gradeSection,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Text(
          entry.teacher,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Text(
          entry.room,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        // One line: the Days column is wide enough for every day's chip.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final day in entry.days)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    // Matches the Grade tab's own Grade-column stepper
                    // container in dark mode (RegistrarColors.background)
                    // — the light-mode lavender pill was hardcoded and
                    // never adapted, leaving near-white dark-mode text
                    // sitting on the same light lavender fill.
                    color: context.isDarkMode
                        ? RegistrarColors.background(context)
                        : RegistrarColors.lightLavender,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    day,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: RegistrarColors.rowText(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Text(
          entry.timeRange,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableMetaStyle(context),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Enrolling students is the Registrar's job; other roles
            // sharing this table (Scheduling Officer) get no such button.
            if (onEnrollSection != null)
              IconButton(
                icon: const Icon(Icons.group_add_outlined, size: 18),
                tooltip: 'Enroll this section\'s students',
                visualDensity: VisualDensity.compact,
                onPressed: () => onEnrollSection!(entry.id),
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit schedule',
                visualDensity: VisualDensity.compact,
                onPressed: () => onEdit!(entry),
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: 'Delete schedule',
                visualDensity: VisualDensity.compact,
                color: kDangerTextColor,
                onPressed: () => onDelete!(entry),
              ),
          ],
        ),
      ],
    );
  }
}

/// Greys out and disables a field that looks like a normal control but
/// isn't wired to anything real yet (Education Level — see the caption
/// printed under the Wrap that uses this). Prevents the registrar from
/// believing a tap here changes which `class_sections` row is created.
class _NotYetWiredField extends StatelessWidget {
  const _NotYetWiredField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Not yet wired — every class section is College-level '
          'regardless of this selection.',
      child: Opacity(
        opacity: 0.5,
        child: IgnorePointer(child: child),
      ),
    );
  }
}

class _EducationLevelField extends StatelessWidget {
  const _EducationLevelField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Education Level'),
        EducationLevelToggle(value: value, onChanged: onChanged, spacing: 10),
      ],
    );
  }
}

class _SectionDropdown extends StatelessWidget {
  const _SectionDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final List<SectionOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppPopupDropdown<String>(
      label: 'Section',
      value: selectedId,
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option.id,
            child: Text(option.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _TermDropdown extends StatelessWidget {
  const _TermDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppPopupDropdown<String>(
      label: 'Term',
      value: value,
      items: const [
        DropdownMenuItem(value: '1st Semester', child: Text('1st Semester')),
        DropdownMenuItem(value: '2nd Semester', child: Text('2nd Semester')),
      ],
      onChanged: onChanged,
    );
  }
}

/// School Year (and Room when no `rooms` rows could be loaded) — free text.
class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AppPopupTextField(
      label: label,
      controller: controller,
    );
  }
}

/// A read-only field in the popup form's field style that runs [onTap]
/// instead of taking typed text — the shell of the searchable and time
/// pickers below.
class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.text,
    required this.placeholder,
    required this.icon,
    required this.onTap,
  });

  final String label;

  /// The chosen value's text, or null while nothing is chosen.
  final String? text;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final style = appPopupFieldStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPopupFieldLabel(label, isDarkMode: c.dark),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: appPopupInputDecoration(
              context,
              isDarkMode: c.dark,
              suffixIcon: Icon(icon, size: 20, color: c.muted),
            ),
            child: Text(
              text ?? placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text == null ? style.copyWith(color: c.muted) : style,
            ),
          ),
        ),
      ],
    );
  }
}

/// Subject / Teacher: tapping opens a dialog with a search box over the
/// options, instead of a plain dropdown that has to be scrolled.
class _SearchableSelectField extends StatelessWidget {
  const _SearchableSelectField({
    required this.label,
    required this.placeholder,
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final String placeholder;
  final List<({String id, String label})> options;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    String? text;
    for (final o in options) {
      if (o.id == selectedId) text = o.label;
    }
    return _TapField(
      label: label,
      text: text,
      placeholder: placeholder,
      icon: Icons.search_rounded,
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => _SearchSelectDialog(
            title: label,
            options: options,
            selectedId: selectedId,
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _SearchSelectDialog extends StatefulWidget {
  const _SearchSelectDialog({
    required this.title,
    required this.options,
    required this.selectedId,
  });

  final String title;
  final List<({String id, String label})> options;
  final String? selectedId;

  @override
  State<_SearchSelectDialog> createState() => _SearchSelectDialogState();
}

class _SearchSelectDialogState extends State<_SearchSelectDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final tokens = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final visible = [
      for (final o in widget.options)
        if (tokens.every(o.label.toLowerCase().contains)) o,
    ];
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPopupHeader(
                title: 'Select ${widget.title}',
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: appPopupFieldStyle(context),
                cursorColor: AppPopupColors.accent,
                decoration: appPopupInputDecoration(
                  context,
                  hint: 'Search ${widget.title.toLowerCase()}',
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 20, color: c.muted),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: visible.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No matches.',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: c.muted),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final o = visible[i];
                          final selected = o.id == widget.selectedId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(context).pop(o.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      o.label,
                                      style:
                                          appPopupFieldStyle(context).copyWith(
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check_rounded,
                                        size: 18, color: AppPopupColors.accent),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Start / End Time: tapping opens the platform time picker, so a time is
/// always valid and never typed.
class _TimePickerField extends StatelessWidget {
  const _TimePickerField({
    required this.label,
    required this.value,
    required this.initialTime,
    required this.onChanged,
  });

  final String label;
  final TimeOfDay? value;
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    return _TapField(
      label: label,
      text: value == null
          ? null
          : MaterialLocalizations.of(context).formatTimeOfDay(value!),
      placeholder: 'Select time',
      icon: Icons.schedule_rounded,
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? initialTime,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _LabeledMultiPillGroup extends StatelessWidget {
  const _LabeledMultiPillGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggled,
  });

  final String label;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final option in options)
              SizedBox(
                width: 49,
                child: _CompactSelectionPill(
                  label: option,
                  isSelected: selected.contains(option),
                  onTap: () => onToggled(option),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Same visuals as [SelectionPill] but with tighter horizontal padding so it
/// fits inside the Figma-spec 49px Year Level / Section / Days pills.
class _CompactSelectionPill extends StatelessWidget {
  const _CompactSelectionPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? RegistrarColors.azureBlue
          : RegistrarColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: kDashboardControlHeight,
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color:
                  isSelected ? Colors.white : RegistrarColors.rowText(context),
            ),
          ),
        ),
      ),
    );
  }
}
