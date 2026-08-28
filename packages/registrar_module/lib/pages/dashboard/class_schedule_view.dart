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

// ---------------------------------------------------------------------------
// Class Schedule tab — "Add Class Schedule" form + schedule table.
// ---------------------------------------------------------------------------

class ClassScheduleView extends StatefulWidget {
  const ClassScheduleView({super.key, required this.entries, this.onSaveChanges});

  final List<ScheduleEntryModel> entries;

  /// Called when "Save Changes" is tapped in the Add Class Schedule card.
  /// Falls back to no-op when omitted (demo behavior).
  final VoidCallback? onSaveChanges;

  @override
  State<ClassScheduleView> createState() => _ClassScheduleViewState();
}

class _ClassScheduleViewState extends State<ClassScheduleView> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;
  int _currentPage = 1;

  String _educationLevel = 'College';
  String _yearLevel = '4th';
  final Set<String> _selectedDays = {'Mon', 'Thu', 'Fri'};
  String _section = 'A';

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
          onSaveChanges: widget.onSaveChanges,
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
              const SizedBox(
                width: 370,
                child: _LabeledDropdown(
                  label: 'Subject',
                  value: 'Computer Programming 2',
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
              const SizedBox(
                width: 370,
                child: _LabeledDropdown(label: 'Teacher', value: 'Mr. Clark Gillerdo'),
              ),
              const SizedBox(
                width: 159,
                child: _LabeledDropdown(label: 'Room', value: 'CL03'),
              ),
              const SizedBox(
                width: 185,
                child: _LabeledDropdown(
                    label: 'Time Slot', value: '8:30 AM - 10:00 AM'),
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

class _LabeledDropdown extends StatelessWidget {
  const _LabeledDropdown({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        DropdownField(value: value),
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
