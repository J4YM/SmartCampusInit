import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../rfid_student_row.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'shared_form_widgets.dart';

const _courseOptions = [
  'All Courses',
  'BS Business Administration',
  'BS Hospitality Management',
  'BS Information Technology',
  'BS Tourism Management',
];
const _yearLevelOptions = [
  'All Years',
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year'
];

class StudentRecordsTab extends StatelessWidget {
  const StudentRecordsTab({
    super.key,
    required this.students,
    required this.isLoading,
    required this.isBusy,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.selectedCourse,
    required this.selectedYearLevel,
    required this.selectedSection,
    required this.sectionOptions,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onYearLevelChanged,
    required this.onSectionChanged,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onSave,
    required this.onDelete,
    this.onPrintId,
  });

  final List<RfidStudentRow> students;
  final bool isLoading;
  final bool isBusy;
  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final String selectedCourse;
  final String selectedYearLevel;
  final String selectedSection;
  final List<String> sectionOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCourseChanged;
  final ValueChanged<String> onYearLevelChanged;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final Future<void> Function(
      RfidRegistrationForm form, RfidStudentRow? editing) onSave;
  final Future<void> Function(RfidStudentRow student) onDelete;

  /// Opens the ID-card capture/print flow. No "Print ID" button at all when
  /// omitted (demo behavior — nowhere to actually print).
  final ValueChanged<RfidStudentRow>? onPrintId;

  void _openRegisterDialog(BuildContext context, {RfidStudentRow? editing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _StudentFormDialog(editing: editing, onSave: onSave),
    );
  }

  void _confirmDelete(BuildContext context, RfidStudentRow student) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => DialogShell(
        title: 'Delete ${student.fullName}?',
        onClose: () => Navigator.of(dialogContext).pop(),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: ItTechnicianColors.dangerRed, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This permanently removes student number ${student.studentNumber} '
                'and cannot be undone.',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
            ),
          ],
        ),
        actions: [
          PaleButton(
            label: 'Cancel',
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
          const SizedBox(width: 10),
          PillButton(
            label: 'Delete',
            background: ItTechnicianColors.dangerRed,
            onTap: () {
              Navigator.of(dialogContext).pop();
              onDelete(student);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same duality as RfidReaderManagementPage's own body builder: this card
    // is used standalone-bounded (a bare Scaffold body — needs the table
    // region to be Expanded + internally scrolling so 25 rows don't overflow
    // past the viewport) and embedded in the IT Technician dashboard, whose
    // mobile/desktop layout puts this inside its own outer, unbounded-height
    // SingleChildScrollView (Expanded would throw there — the table has to
    // size to its own natural height instead and let that ambient scroll
    // view do the scrolling).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final tableRegion = isLoading && students.isEmpty
            ? const _SkeletonTableBody(rowCount: 8)
            : students.isEmpty
                ? Center(
                    child: Text(
                      'No students match these filters.',
                      style: GoogleFonts.poppins(
                          color: ItTechnicianColors.mutedText(context)),
                    ),
                  )
                : _StudentTable(
                    students: students,
                    isBusy: isBusy,
                    onEdit: (s) => _openRegisterDialog(context, editing: s),
                    onDelete: (s) => _confirmDelete(context, s),
                    onPrintId: onPrintId,
                  );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ItTechnicianColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ItTechnicianColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Student Records',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: ItTechnicianColors.rowText(context),
                      ),
                    ),
                  ),
                  PillButton(
                    label: 'Register Student',
                    icon: Icons.add_rounded,
                    onTap: () => _openRegisterDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _YearLevelQuickTabs(
                  selected: selectedYearLevel, onChanged: onYearLevelChanged),
              const SizedBox(height: 12),
              _FilterRow(
                selectedCourse: selectedCourse,
                selectedSection: selectedSection,
                sectionOptions: sectionOptions,
                onSearchChanged: onSearchChanged,
                onCourseChanged: onCourseChanged,
                onSectionChanged: onSectionChanged,
              ),
              const SizedBox(height: 16),
              bounded ? Expanded(child: tableRegion) : tableRegion,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    totalCount == null
                        ? 'Page $currentPage of $totalPages'
                        : 'Page $currentPage of $totalPages · $totalCount total',
                    style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 10 : 12, color: ItTechnicianColors.mutedText(context)),
                  ),
                  Row(
                    children: [
                      PaginationPillButton(
                        label: 'Previous',
                        background: ItTechnicianColors.background(context),
                        foreground: ItTechnicianColors.azureBlue,
                        onTap: (isLoading || currentPage <= 1)
                            ? null
                            : onPreviousPage,
                      ),
                      const SizedBox(width: 8),
                      PaginationPillButton(
                        label: 'Next',
                        background: ItTechnicianColors.azureBlue,
                        foreground: Colors.white,
                        onTap: (isLoading || currentPage >= totalPages)
                            ? null
                            : onNextPage,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _YearLevelQuickTabs extends StatelessWidget {
  const _YearLevelQuickTabs({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final year in _yearLevelOptions) ...[
            FilterPill(
              label: year,
              isSelected: year == selected,
              onTap: () => onChanged(year),
            ),
            if (year != _yearLevelOptions.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatefulWidget {
  const _FilterRow({
    required this.selectedCourse,
    required this.selectedSection,
    required this.sectionOptions,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onSectionChanged,
  });

  final String selectedCourse;
  final String selectedSection;
  final List<String> sectionOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCourseChanged;
  final ValueChanged<String> onSectionChanged;

  @override
  State<_FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends State<_FilterRow> {
  final _searchController = TextEditingController();

  /// Each keystroke otherwise fires a full paginated Supabase query (with an
  /// exact-count scan) via [_FilterRow.onSearchChanged], so fast typing
  /// stacks up overlapping requests whose out-of-order responses can clobber
  /// each other. Coalesce them into one query per typing pause.
  static const _searchDebounceDuration = Duration(milliseconds: 350);
  Timer? _searchDebounce;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      _searchDebounceDuration,
      () => widget.onSearchChanged(value),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final search = TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: fieldTextStyle(context),
          decoration: fieldDecoration(
            context,
            hintText: 'Search by student number...',
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: ItTechnicianColors.mutedText(context),
            ),
          ),
        );
        final courseDropdown = DropdownButtonFormField<String>(
          value: widget.selectedCourse,
          isExpanded: true,
          icon: dropdownArrowIcon(context),
          style: fieldTextStyle(context),
          dropdownColor: ItTechnicianColors.card(context),
          decoration: fieldDecoration(context),
          items: _courseOptions
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (value) {
            if (value != null) widget.onCourseChanged(value);
          },
        );
        final sectionOptions = ['All Sections', ...widget.sectionOptions];
        final sectionDropdown = DropdownButtonFormField<String>(
          value: sectionOptions.contains(widget.selectedSection)
              ? widget.selectedSection
              : 'All Sections',
          isExpanded: true,
          icon: dropdownArrowIcon(context),
          style: fieldTextStyle(context),
          dropdownColor: ItTechnicianColors.card(context),
          decoration: fieldDecoration(context),
          items: sectionOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (value) {
            if (value != null) widget.onSectionChanged(value);
          },
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: courseDropdown),
                const SizedBox(width: 10),
                Expanded(child: sectionDropdown)
              ]),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 3, child: search),
            const SizedBox(width: 10),
            SizedBox(width: 220, child: courseDropdown),
            const SizedBox(width: 10),
            SizedBox(width: 160, child: sectionDropdown),
          ],
        );
      },
    );
  }
}

class _SkeletonTableBody extends StatefulWidget {
  const _SkeletonTableBody({required this.rowCount});
  final int rowCount;

  @override
  State<_SkeletonTableBody> createState() => _SkeletonTableBodyState();
}

class _SkeletonTableBodyState extends State<_SkeletonTableBody>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final _opacity = Tween<double>(begin: 0.4, end: 0.9)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.rowCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: ItTechnicianColors.cardBorder(context).withOpacity(_opacity.value),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentTable extends StatelessWidget {
  const _StudentTable(
      {required this.students,
      required this.isBusy,
      required this.onEdit,
      required this.onDelete,
      this.onPrintId});

  final List<RfidStudentRow> students;
  final bool isBusy;
  final ValueChanged<RfidStudentRow> onEdit;
  final ValueChanged<RfidStudentRow> onDelete;

  /// Opens the ID-card capture/print flow. No "Print ID" button at all when
  /// omitted (demo behavior — nowhere to actually print).
  final ValueChanged<RfidStudentRow>? onPrintId;

  @override
  Widget build(BuildContext context) {
    final headingStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    final dataStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: ItTechnicianColors.rowText(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // SingleChildScrollView already sizes to its child's natural height
        // when given an unbounded ambient height (no shrinkWrap needed,
        // unlike ListView) — the dashboard page's own outer scroll handles
        // reaching all of a full page of rows (25 by default). Horizontal
        // scroll (inner) keeps the wide table usable on narrow screens.
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(ItTechnicianColors.navyBlue),
                // Matches Registrar's own Student Records table header height
                // (its custom Row-based header renders at 58px).
                headingRowHeight: 58,
                headingTextStyle: headingStyle,
                dataTextStyle: dataStyle,
                dividerThickness: 1,
                columns: const [
                  DataColumn(label: Text('RFID No.')),
                  DataColumn(label: Text('Student Number')),
                  DataColumn(label: Text('Full Name')),
                  DataColumn(label: Text('Course')),
                  DataColumn(label: Text('Year Level')),
                  DataColumn(label: Text('Section')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: students
                    .map(
                      (student) => DataRow(
                        cells: [
                          DataCell(Text(student.rfidNo)),
                          DataCell(Text(student.studentNumber)),
                          DataCell(Text(student.fullName)),
                          DataCell(Text(student.course)),
                          DataCell(Text(student.yearLevel)),
                          DataCell(Text(student.section)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onPrintId != null)
                                  IconButton(
                                    tooltip: 'Print student ID',
                                    icon: const Icon(Icons.badge_outlined),
                                    color: ItTechnicianColors.azureBlue,
                                    onPressed: () => onPrintId!(student),
                                  ),
                                IconButton(
                                  tooltip: 'Edit student',
                                  icon: const Icon(Icons.edit_outlined),
                                  color: ItTechnicianColors.azureBlue,
                                  onPressed: () => onEdit(student),
                                ),
                                IconButton(
                                  tooltip: 'Delete student',
                                  icon: const Icon(Icons.delete_outline,
                                      color: ItTechnicianColors.dangerRed),
                                  onPressed:
                                      isBusy ? null : () => onDelete(student),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({required this.editing, required this.onSave});

  final RfidStudentRow? editing;
  final Future<void> Function(
      RfidRegistrationForm form, RfidStudentRow? editing) onSave;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  late final _rfidController =
      TextEditingController(text: widget.editing?.rfidNo ?? '');
  late final _studentNumberController =
      TextEditingController(text: widget.editing?.studentNumber ?? '');
  late final _firstNameController =
      TextEditingController(text: widget.editing?.firstName ?? '');
  late final _lastNameController =
      TextEditingController(text: widget.editing?.lastName ?? '');
  late final _middleInitialController =
      TextEditingController(text: widget.editing?.middleInitial ?? '');
  late final _sectionController =
      TextEditingController(text: widget.editing?.section ?? '');
  late final _guardianController =
      TextEditingController(text: widget.editing?.guardianName ?? '');
  String? _course;
  String? _yearLevel;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _course = widget.editing?.course;
    _yearLevel = widget.editing?.yearLevel;
  }

  @override
  void dispose() {
    _rfidController.dispose();
    _studentNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _sectionController.dispose();
    _guardianController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final course = _course;
    final yearLevel = _yearLevel;
    if (_rfidController.text.trim().isEmpty ||
        _studentNumberController.text.trim().isEmpty ||
        _firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _sectionController.text.trim().isEmpty ||
        course == null ||
        yearLevel == null) {
      setState(() => _error = 'Please complete all required fields.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        RfidRegistrationForm(
          rfidNo: _rfidController.text.trim(),
          studentNumber: _studentNumberController.text.trim(),
          firstName: _firstNameController.text.trim(),
          middleInitial: _middleInitialController.text.trim(),
          lastName: _lastNameController.text.trim(),
          course: course,
          yearLevel: yearLevel,
          section: _sectionController.text.trim(),
          guardianName: _guardianController.text.trim(),
        ),
        widget.editing,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseItems = _courseOptions.skip(1).toList();
    final yearItems = _yearLevelOptions.skip(1).toList();

    return DialogShell(
      title: widget.editing == null ? 'Register Student' : 'Edit Student',
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      width: 440,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 10 : 12,
                fontWeight: FontWeight.w500,
                color: ItTechnicianColors.dangerRed,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const FieldLabel('RFID No.'),
          TextField(
            controller: _rfidController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Student Number'),
          TextField(
            controller: _studentNumberController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Course'),
          DropdownButtonFormField<String>(
            value: _course,
            isExpanded: true,
            icon: dropdownArrowIcon(context),
            style: fieldTextStyle(context),
            dropdownColor: ItTechnicianColors.card(context),
            decoration: fieldDecoration(context),
            items: courseItems
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged:
                _saving ? null : (value) => setState(() => _course = value),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Year Level'),
          DropdownButtonFormField<String>(
            value: _yearLevel,
            isExpanded: true,
            icon: dropdownArrowIcon(context),
            style: fieldTextStyle(context),
            dropdownColor: ItTechnicianColors.card(context),
            decoration: fieldDecoration(context),
            items: yearItems
                .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                .toList(),
            onChanged:
                _saving ? null : (value) => setState(() => _yearLevel = value),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Section'),
          TextField(
            controller: _sectionController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
          const SizedBox(height: 14),
          const FieldLabel('First Name'),
          TextField(
            controller: _firstNameController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Last Name'),
          TextField(
            controller: _lastNameController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
          const SizedBox(height: 14),
          const FieldLabel('M.I.'),
          TextField(
            controller: _middleInitialController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Parent/Guardian Name'),
          TextField(
            controller: _guardianController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
        ],
      ),
      actions: [
        PaleButton(
          label: 'Cancel',
          onTap: _saving ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        _saving
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        ItTechnicianColors.azureBlue),
                  ),
                ),
              )
            : PillButton(
                label: widget.editing == null ? 'Register' : 'Save Changes',
                onTap: _save,
              ),
      ],
    );
  }
}
