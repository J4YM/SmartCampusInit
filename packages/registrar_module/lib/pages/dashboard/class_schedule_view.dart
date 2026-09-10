import 'package:dashboard_layout/dashboard_layout.dart';
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
  const SubjectOption({required this.id, required this.code, required this.title});

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
  });

  final List<ScheduleEntryModel> entries;
  final List<SubjectOption> subjectOptions;
  final List<TeacherOption> teacherOptions;

  /// Called with the assembled form values when "Save Changes" is tapped.
  /// Falls back to no-op when omitted (demo behavior).
  final void Function({
    required String subjectId,
    required String professorId,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  })? onSaveChanges;

  @override
  State<ClassScheduleView> createState() => _ClassScheduleViewState();
}

class _ClassScheduleViewState extends State<ClassScheduleView> {
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  String _educationLevel = 'College';
  String _yearLevel = '4th';
  final Set<String> _selectedDays = {'Mon', 'Thu', 'Fri'};
  String _section = 'A';

  String? _selectedSubjectId;
  String? _selectedProfessorId;
  late final TextEditingController _roomController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;

  @override
  void initState() {
    super.initState();
    _roomController = TextEditingController();
    _startTimeController = TextEditingController();
    _endTimeController = TextEditingController();
  }

  @override
  void dispose() {
    _roomController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  void _handleSaveChanges() {
    final subjectId = _selectedSubjectId;
    final professorId = _selectedProfessorId;
    final room = _roomController.text.trim();
    final startTime = _startTimeController.text.trim();
    final endTime = _endTimeController.text.trim();
    if (subjectId == null ||
        professorId == null ||
        room.isEmpty ||
        startTime.isEmpty ||
        endTime.isEmpty ||
        _selectedDays.isEmpty) {
      return;
    }
    widget.onSaveChanges?.call(
      subjectId: subjectId,
      professorId: professorId,
      room: room,
      days: _selectedDays.toList(),
      startTime: startTime,
      endTime: endTime,
    );
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
          yearLevel: _yearLevel,
          onYearLevelChanged: (v) => setState(() => _yearLevel = v),
          section: _section,
          onSectionChanged: (v) => setState(() => _section = v),
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
          roomController: _roomController,
          startTimeController: _startTimeController,
          endTimeController: _endTimeController,
          onSaveChanges: _handleSaveChanges,
        ),
        const SizedBox(height: 18),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
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
                for (final entry in pageEntries) _ScheduleRow(entry: entry),
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
          Expanded(
              flex: 2, child: Text('Grade & Section', style: style)),
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
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.entry});

  final ScheduleEntryModel entry;

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
        ],
      ),
    );
  }
}

class _AddClassScheduleCard extends StatelessWidget {
  const _AddClassScheduleCard({
    required this.educationLevel,
    required this.onEducationLevelChanged,
    required this.yearLevel,
    required this.onYearLevelChanged,
    required this.section,
    required this.onSectionChanged,
    required this.selectedDays,
    required this.onDayToggled,
    required this.subjectOptions,
    required this.selectedSubjectId,
    required this.onSubjectChanged,
    required this.teacherOptions,
    required this.selectedProfessorId,
    required this.onProfessorChanged,
    required this.roomController,
    required this.startTimeController,
    required this.endTimeController,
    this.onSaveChanges,
  });

  final String educationLevel;
  final ValueChanged<String> onEducationLevelChanged;
  final String yearLevel;
  final ValueChanged<String> onYearLevelChanged;
  final String section;
  final ValueChanged<String> onSectionChanged;
  final Set<String> selectedDays;
  final ValueChanged<String> onDayToggled;
  final List<SubjectOption> subjectOptions;
  final String? selectedSubjectId;
  final ValueChanged<String?> onSubjectChanged;
  final List<TeacherOption> teacherOptions;
  final String? selectedProfessorId;
  final ValueChanged<String?> onProfessorChanged;
  final TextEditingController roomController;
  final TextEditingController startTimeController;
  final TextEditingController endTimeController;
  final VoidCallback? onSaveChanges;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
      ),
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
              const UploadSpreadsheetButton(),
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
                child: _EducationLevelField(
                  value: educationLevel,
                  onChanged: onEducationLevelChanged,
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
              _LabeledPillGroup(
                label: 'Year Level',
                options: const ['1st', '2nd', '3rd', '4th'],
                selected: yearLevel,
                onSelected: onYearLevelChanged,
              ),
              _LabeledPillGroup(
                label: 'Section',
                options: const ['A', 'B', 'C'],
                selected: section,
                onSelected: onSectionChanged,
              ),
            ],
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
          initialValue: selectedId,
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
          initialValue: selectedId,
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

class _LabeledPillGroup extends StatelessWidget {
  const _LabeledPillGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

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
                  isSelected: selected == option,
                  onTap: () => onSelected(option),
                ),
              ),
          ],
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
              color: isSelected ? Colors.white : RegistrarColors.rowText(context),
            ),
          ),
        ),
      ),
    );
  }
}
