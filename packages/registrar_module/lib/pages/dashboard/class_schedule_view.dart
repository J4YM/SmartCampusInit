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
  });

  final String id;
  final String subject;
  final String gradeSection;
  final String teacher;
  final String room;
  final List<String> days;
  final String timeRange;

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
  });

  final String id;
  final String name; // e.g. "BSIT-3B"
  final int yearLevel; // e.g. 3
}

// ---------------------------------------------------------------------------
// Class Schedule tab — "Add Class Schedule" form + schedule table.
// ---------------------------------------------------------------------------

class ClassScheduleView extends StatefulWidget {
  const ClassScheduleView({
    super.key,
    required this.entries,
    this.onSaveChanges,
    this.subjectOptions = const [],
    this.teacherOptions = const [],
    this.sectionOptions = const [],
    this.onEnrollSection,
    this.onImportSchedule,
  });

  final List<ScheduleEntryModel> entries;
  final List<SubjectOption> subjectOptions;
  final List<TeacherOption> teacherOptions;
  final List<SectionOption> sectionOptions;

  /// Called with the assembled form values when "Save Changes" is tapped.
  /// Falls back to no-op when omitted (demo behavior).
  final void Function({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  })? onSaveChanges;

  /// Called with a row's `class_sections.id` when its "Enroll this
  /// section's students" button is tapped. Falls back to a disabled button
  /// when omitted (demo behavior).
  final ValueChanged<String>? onEnrollSection;

  /// Runs a picked Excel file (Classes+Professor list, Confirmation of
  /// Faculty Loading, or Room Schedule export) through the schedule
  /// import pipeline, tagged with whatever School Year/Term this form's
  /// own fields currently hold. Falls back to a confirmation snackbar via
  /// [UploadSpreadsheetButton]'s own default when omitted (demo
  /// behavior — matches every other not-yet-wired callback here).
  final Future<void> Function({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  })? onImportSchedule;

  @override
  State<ClassScheduleView> createState() => _ClassScheduleViewState();
}

class _ClassScheduleViewState extends State<ClassScheduleView> {
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  String _educationLevel = 'College';
  final Set<String> _selectedDays = {'Mon', 'Thu', 'Fri'};

  String? _selectedSubjectId;
  String? _selectedProfessorId;
  String? _selectedSectionId;
  late final TextEditingController _roomController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  late final TextEditingController _schoolYearController;
  String _term = '1st Semester';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _roomController = TextEditingController();
    _startTimeController = TextEditingController();
    _endTimeController = TextEditingController();
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    _schoolYearController =
        TextEditingController(text: '$startYear-${startYear + 1}');
  }

  @override
  void dispose() {
    _roomController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _schoolYearController.dispose();
    super.dispose();
  }

  void _handleSaveChanges() {
    final subjectId = _selectedSubjectId;
    final professorId = _selectedProfessorId;
    final sectionId = _selectedSectionId;
    final schoolYear = _schoolYearController.text.trim();
    final room = _roomController.text.trim();
    final startTime = _startTimeController.text.trim();
    final endTime = _endTimeController.text.trim();
    if (subjectId == null ||
        professorId == null ||
        sectionId == null ||
        schoolYear.isEmpty ||
        room.isEmpty ||
        startTime.isEmpty ||
        endTime.isEmpty ||
        _selectedDays.isEmpty) {
      return;
    }
    widget.onSaveChanges?.call(
      subjectId: subjectId,
      professorId: professorId,
      sectionId: sectionId,
      schoolYear: schoolYear,
      term: _term,
      room: room,
      days: _selectedDays.toList(),
      startTime: startTime,
      endTime: endTime,
    );
  }

  Future<void> _handleImportFile(PlatformFile file) async {
    final onImportSchedule = widget.onImportSchedule;
    final bytes = file.bytes;
    if (onImportSchedule == null || bytes == null || _importing) return;
    final schoolYear = _schoolYearController.text.trim();
    if (schoolYear.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a School Year before importing a file.'),
      ));
      return;
    }
    setState(() => _importing = true);
    try {
      await onImportSchedule(bytes: bytes, schoolYear: schoolYear, term: _term);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final totalPages =
        entries.isEmpty ? 1 : (entries.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageEntries =
        entries.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AddClassScheduleCard(
          educationLevel: _educationLevel,
          onEducationLevelChanged: (v) => setState(() => _educationLevel = v),
          selectedDays: _selectedDays,
          onDayToggled: (day) => setState(() {
            _selectedDays.contains(day)
                ? _selectedDays.remove(day)
                : _selectedDays.add(day);
          }),
          subjectOptions: widget.subjectOptions,
          selectedSubjectId: _selectedSubjectId,
          onSubjectChanged: (v) => setState(() => _selectedSubjectId = v),
          teacherOptions: widget.teacherOptions,
          selectedProfessorId: _selectedProfessorId,
          onProfessorChanged: (v) => setState(() => _selectedProfessorId = v),
          sectionOptions: widget.sectionOptions,
          selectedSectionId: _selectedSectionId,
          onSectionChanged: (v) => setState(() => _selectedSectionId = v),
          roomController: _roomController,
          startTimeController: _startTimeController,
          endTimeController: _endTimeController,
          schoolYearController: _schoolYearController,
          term: _term,
          onTermChanged: (v) {
            if (v != null) setState(() => _term = v);
          },
          onSaveChanges: _handleSaveChanges,
          onFileSelected: _handleImportFile,
          importing: _importing,
        ),
        const SizedBox(height: 18),
        BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(
                  'Student List',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
                ),
              ),
              const _ScheduleHeaderRow(),
              if (pageEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No class schedules yet',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: RegistrarColors.mutedText(context),
                      ),
                    ),
                  ),
                )
              else
                for (final entry in pageEntries)
                  _ScheduleRow(
                    entry: entry,
                    onEnrollSection: widget.onEnrollSection,
                  ),
              if (entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: PillPaginationFooter(
                    shownCount: pageEntries.length,
                    totalCount: entries.length,
                    label: 'total student grade records',
                    canGoPrevious: currentPage > 1,
                    canGoNext: currentPage < totalPages,
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () =>
                        setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleHeaderRow extends StatelessWidget {
  const _ScheduleHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: RegistrarColors.navyBlue,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Subject', style: style)),
          Expanded(flex: 2, child: Text('Grade & Section', style: style)),
          Expanded(flex: 2, child: Text('Teacher', style: style)),
          Expanded(child: Text('Room', style: style)),
          Expanded(
            flex: 2,
            child: Text('Days', textAlign: TextAlign.center, style: style),
          ),
          Expanded(
            flex: 2,
            child: Text('Time', textAlign: TextAlign.center, style: style),
          ),
          Expanded(child: Text('', style: style)),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.entry, this.onEnrollSection});

  final ScheduleEntryModel entry;
  final ValueChanged<String>? onEnrollSection;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: RegistrarColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: RegistrarColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(entry.subject, style: style)),
          Expanded(flex: 2, child: Text(entry.gradeSection, style: style)),
          Expanded(flex: 2, child: Text(entry.teacher, style: style)),
          Expanded(child: Text(entry.room, style: style)),
          Expanded(
            flex: 2,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final day in entry.days)
                  Container(
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
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.timeRange,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.group_add_outlined, size: 18),
              tooltip: 'Enroll this section\'s students',
              onPressed: onEnrollSection == null
                  ? null
                  : () => onEnrollSection!(entry.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddClassScheduleCard extends StatelessWidget {
  const _AddClassScheduleCard({
    required this.educationLevel,
    required this.onEducationLevelChanged,
    required this.selectedDays,
    required this.onDayToggled,
    required this.subjectOptions,
    required this.selectedSubjectId,
    required this.onSubjectChanged,
    required this.teacherOptions,
    required this.selectedProfessorId,
    required this.onProfessorChanged,
    required this.sectionOptions,
    required this.selectedSectionId,
    required this.onSectionChanged,
    required this.roomController,
    required this.startTimeController,
    required this.endTimeController,
    required this.schoolYearController,
    required this.term,
    required this.onTermChanged,
    this.onSaveChanges,
    this.onFileSelected,
    this.importing = false,
  });

  final String educationLevel;
  final ValueChanged<String> onEducationLevelChanged;
  final Set<String> selectedDays;
  final ValueChanged<String> onDayToggled;
  final List<SubjectOption> subjectOptions;
  final String? selectedSubjectId;
  final ValueChanged<String?> onSubjectChanged;
  final List<TeacherOption> teacherOptions;
  final String? selectedProfessorId;
  final ValueChanged<String?> onProfessorChanged;
  final List<SectionOption> sectionOptions;
  final String? selectedSectionId;
  final ValueChanged<String?> onSectionChanged;
  final TextEditingController roomController;
  final TextEditingController startTimeController;
  final TextEditingController endTimeController;
  final TextEditingController schoolYearController;
  final String term;
  final ValueChanged<String?> onTermChanged;
  final VoidCallback? onSaveChanges;
  final ValueChanged<PlatformFile>? onFileSelected;
  final bool importing;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add Class Schedule',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
                ),
              ),
              if (importing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                UploadSpreadsheetButton(onFileSelected: onFileSelected),
              const SizedBox(width: 8),
              SaveChangesButton(onTap: onSaveChanges ?? () {}),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 26,
            runSpacing: 20,
            children: [
              SizedBox(
                width: 370,
                child: _NotYetWiredField(
                  child: _EducationLevelField(
                    value: educationLevel,
                    onChanged: onEducationLevelChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 370,
                child: _SubjectDropdown(
                  options: subjectOptions,
                  selectedId: selectedSubjectId,
                  onChanged: onSubjectChanged,
                ),
              ),
              SizedBox(
                width: 370,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionDropdown(
                      options: sectionOptions,
                      selectedId: selectedSectionId,
                      onChanged: onSectionChanged,
                    ),
                    if (selectedSectionId != null)
                      Builder(builder: (context) {
                        SectionOption? selected;
                        for (final option in sectionOptions) {
                          if (option.id == selectedSectionId) {
                            selected = option;
                            break;
                          }
                        }
                        if (selected == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Year ${selected.yearLevel}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: RegistrarColors.mutedText(context),
                            ),
                          ),
                        );
                      }),
                  ],
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
          const SizedBox(height: 20),
          Wrap(
            spacing: 26,
            runSpacing: 20,
            children: [
              SizedBox(
                width: 370,
                child: _TeacherDropdown(
                  options: teacherOptions,
                  selectedId: selectedProfessorId,
                  onChanged: onProfessorChanged,
                ),
              ),
              SizedBox(
                width: 159,
                child: _LabeledTextField(
                  label: 'Room',
                  controller: roomController,
                ),
              ),
              SizedBox(
                width: 185,
                child: _LabeledTextField(
                  label: 'Start Time',
                  controller: startTimeController,
                ),
              ),
              SizedBox(
                width: 185,
                child: _LabeledTextField(
                  label: 'End Time',
                  controller: endTimeController,
                ),
              ),
              SizedBox(
                width: 185,
                child: _LabeledTextField(
                  label: 'School Year',
                  controller: schoolYearController,
                ),
              ),
              SizedBox(
                width: 185,
                child: _TermDropdown(value: term, onChanged: onTermChanged),
              ),
              _LabeledMultiPillGroup(
                label: 'Days',
                options: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
                selected: selectedDays,
                onToggled: onDayToggled,
              ),
            ],
          ),
        ],
      ),
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

class _SubjectDropdown extends StatelessWidget {
  const _SubjectDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final List<SubjectOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Subject'),
        DropdownButtonFormField<String>(
          value: selectedId,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.label)),
          ],
          onChanged: onChanged,
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Section'),
        DropdownButtonFormField<String>(
          value: selectedId,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.name)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _TeacherDropdown extends StatelessWidget {
  const _TeacherDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final List<TeacherOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Teacher'),
        DropdownButtonFormField<String>(
          value: selectedId,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.fullName)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _TermDropdown extends StatelessWidget {
  const _TermDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Term'),
        DropdownButtonFormField<String>(
          value: value,
          items: const [
            DropdownMenuItem(
                value: '1st Semester', child: Text('1st Semester')),
            DropdownMenuItem(
                value: '2nd Semester', child: Text('2nd Semester')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Room / Start Time / End Time — free text, since there's no `rooms`/
/// `time_slots` reference table to populate a dropdown from (unlike Subject
/// and Teacher above).
class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: RegistrarColors.background(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
          ),
        ),
      ],
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
          height: 35,
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
