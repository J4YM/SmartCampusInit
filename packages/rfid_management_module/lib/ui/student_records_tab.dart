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
    required this.onSearchChanged,
    this.sectionFilter,
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
  final ValueChanged<String> onSearchChanged;

  /// The Filter button's section list (single section or "All sections"),
  /// owned by the host that holds the filter state. Null hides the button.
  final FilterSectionPicker? sectionFilter;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final Future<void> Function(
      RfidRegistrationForm form, RfidStudentRow? editing) onSave;
  final Future<void> Function(RfidStudentRow student) onDelete;

  /// Opens the ID-card capture/print flow. No "Print ID" button at all when
  /// omitted (demo behavior — nowhere to actually print).
  final ValueChanged<RfidStudentRow>? onPrintId;

  void _openRegisterDialog(BuildContext context, {RfidStudentRow? editing}) {
    // showDialog inserts its subtree into the root Navigator's Overlay, a
    // sibling of this page's own local Theme — not a descendant of it — so
    // context.isDarkMode inside the dialog (and the shared DialogShell/
    // PillButton/PaleButton widgets it's built from) would otherwise see the
    // app's ambient theme instead of this dashboard's actual toggle.
    // Capturing Theme.of(context) here, while still inside the local Theme,
    // and re-applying it fixes that for the dialog's whole subtree.
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: _StudentFormDialog(editing: editing, onSave: onSave),
      ),
    );
  }

  void _confirmDelete(BuildContext context, RfidStudentRow student) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Theme(
        data: theme,
        child: DialogShell(
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
                ? const DashboardTableEmptyState(
                    message: 'No students match these filters.',
                  )
                : _StudentTable(
                    students: students,
                    isBusy: isBusy,
                    onEdit: (s) => _openRegisterDialog(context, editing: s),
                    onDelete: (s) => _confirmDelete(context, s),
                    onPrintId: onPrintId,
                  );

        return SizedBox(
          width: double.infinity,
          child: BentoCard(
            backgroundColor: ItTechnicianColors.card(context),
            borderColor: ItTechnicianColors.cardBorder(context),
            // Flush: the table runs edge to edge (the app-wide table
            // standard), so only the header row is padded, below.
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wide: title at the far left; search + filter and the Register
              // button grouped at the far right, the search capped at 440px
              // like Registrar's Student List. Narrow: the search + filter
              // drop to their own row below.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: LayoutBuilder(
                builder: (context, headerConstraints) {
                  final title = Text(
                    'Student Records',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: ItTechnicianColors.rowText(context),
                    ),
                  );
                  final registerButton = PillButton(
                    label: 'Register Student',
                    icon: Icons.add_rounded,
                    onTap: () => _openRegisterDialog(context),
                  );
                  final filterRow = _FilterRow(
                    onSearchChanged: onSearchChanged,
                    sectionFilter: sectionFilter,
                  );
                  if (headerConstraints.maxWidth < 760) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: title),
                            registerButton,
                          ],
                        ),
                        const SizedBox(height: 16),
                        filterRow,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      title,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 440),
                                  child: filterRow,
                                ),
                              ),
                              const SizedBox(width: 16),
                              registerButton,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
                ),
              ),
              bounded ? Expanded(child: tableRegion) : tableRegion,
              DashboardTableFooter(
                child: CardPaginationFooter(
                  currentPage: currentPage,
                  totalPages: totalPages,
                  totalCount: totalCount,
                  isLoading: isLoading,
                  textColor: ItTechnicianColors.mutedText(context),
                  accentColor: ItTechnicianColors.azureBlue,
                  mutedBackground: ItTechnicianColors.background(context),
                  onPrevious: onPreviousPage,
                  onNext: onNextPage,
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

class _FilterRow extends StatefulWidget {
  const _FilterRow({
    required this.onSearchChanged,
    this.sectionFilter,
  });

  final ValueChanged<String> onSearchChanged;
  final FilterSectionPicker? sectionFilter;

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
    final sectionFilter = widget.sectionFilter;
    return Row(
      children: [
        Expanded(
          // 34px (kDashboardControlHeight), matching the Filter pill beside it (and every other
          // dashboard's search). The prefix icon's default 48px minimum
          // constraint is what made this field 48px tall.
          child: SizedBox(
            height: kDashboardControlHeight,
            child: TextField(
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.center,
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
              ).copyWith(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 40, minHeight: 32),
              ),
            ),
          ),
        ),
        if (sectionFilter != null) ...[
          const SizedBox(width: 10),
          FilterMenuButton(
            sectionFilter: sectionFilter,
            backgroundColor: ItTechnicianColors.fieldFill(context),
            menuColor: ItTechnicianColors.card(context),
            borderColor: ItTechnicianColors.cardBorder(context),
            iconColor: ItTechnicianColors.mutedText(context),
            textColor: ItTechnicianColors.rowText(context),
            mutedTextColor: ItTechnicianColors.mutedText(context),
            accentColor: ItTechnicianColors.azureBlue,
          ),
        ],
      ],
    );
  }
}

/// Was a bespoke `AnimationController` pulsing `cardBorder(context)` — a
/// near-transparent black border token (rgba(0,0,0,0.05) in light mode).
/// `withOpacity()` *replaces* the alpha rather than multiplying it, so that
/// near-invisible border color became a near-solid black bar once the
/// 0.4–0.9 pulse opacity was applied. Now built on the shared
/// [SkeletonPulse]/[SkeletonBox] primitives with [ItTechnicianColors.gray]
/// (an actual light-gray fill), giving a normal pulsing gray placeholder —
/// same shape/timing as before, correct color, and one shared animation
/// driving every row instead of each row (well, previously each build,
/// same controller) animating independently.
class _SkeletonTableBody extends StatelessWidget {
  const _SkeletonTableBody({required this.rowCount});
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      builder: (context, opacity) => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rowCount,
        itemBuilder: (context, index) => Padding(
          // Inset like a real row (and the card's title), so the placeholder
          // bars don't run into the card's edges.
          padding: const EdgeInsets.symmetric(
            horizontal: DashboardTableMetrics.horizontalPadding,
            vertical: 8,
          ),
          child: SkeletonBox(
            color: ItTechnicianColors.gray,
            opacity: opacity,
            height: 40,
            borderRadius: 8,
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

  static const _columns = <DashboardTableColumn>[
    DashboardTableColumn('RFID No.', flex: 2),
    DashboardTableColumn('Student Number', flex: 2),
    DashboardTableColumn('Full Name', flex: 3),
    DashboardTableColumn('Course', flex: 3),
    DashboardTableColumn('Year Level', flex: 2),
    DashboardTableColumn('Section', flex: 2),
    DashboardTableColumn('Actions', flex: 3),
  ];

  /// Below this width the table scrolls sideways instead of squeezing.
  static const _minTableWidth = 960.0;

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView already sizes to its child's natural height
    // when given an unbounded ambient height — the dashboard page's own
    // outer scroll handles reaching all of a full page of rows. When the
    // card IS bounded, this scrolls the rows within it.
    return SingleChildScrollView(
      child: DashboardTableHorizontalScroll(
        minWidth: _minTableWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DashboardTableHeader(columns: _columns, topBorder: true),
            for (var i = 0; i < students.length; i++)
              DashboardTableRow(
                columns: _columns,
                showDivider: i < students.length - 1,
                cells: _cells(context, students[i]),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cells(BuildContext context, RfidStudentRow student) {
    Widget body(String text) => Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        );
    return [
      Text(
        student.rfidNo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: dashboardTableMetaStyle(context),
      ),
      Text(
        student.studentNumber,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: dashboardTableIdStyle(context),
      ),
      Text(
        student.fullName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: dashboardTablePrimaryStyle(context),
      ),
      body(student.course),
      body(student.yearLevel),
      body(student.section),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPrintId != null)
            IconButton(
              tooltip: 'Print student ID',
              icon: const Icon(Icons.badge_outlined),
              color: subNavActiveColor(context, ItTechnicianColors.azureBlue),
              onPressed: () => onPrintId!(student),
            ),
          IconButton(
            tooltip: 'Edit student',
            icon: const Icon(Icons.edit_outlined),
            color: subNavActiveColor(context, ItTechnicianColors.azureBlue),
            onPressed: () => onEdit(student),
          ),
          IconButton(
            tooltip: 'Delete student',
            icon: const Icon(Icons.delete_outline,
                color: ItTechnicianColors.dangerRed),
            onPressed: isBusy ? null : () => onDelete(student),
          ),
        ],
      ),
    ];
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
  late final _guardianContactNoController =
      TextEditingController(text: widget.editing?.guardianContactNo ?? '');
  String? _course;
  String? _yearLevel;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Empty counts as unset: '' would be a dropdown value with no item.
    final course = widget.editing?.course;
    final yearLevel = widget.editing?.yearLevel;
    _course = (course == null || course.isEmpty) ? null : course;
    _yearLevel = (yearLevel == null || yearLevel.isEmpty) ? null : yearLevel;
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
    _guardianContactNoController.dispose();
    super.dispose();
  }

  static List<String> _withCurrent(List<String> options, String? current) =>
      current == null || current.isEmpty || options.contains(current)
          ? options
          : [...options, current];

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
          guardianContactNo: _guardianContactNoController.text.trim(),
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
    // A student's stored course/year isn't always one of the fixed choices
    // — batch enrollment imports keep the file's spelling (e.g. 'BSBA',
    // 'STEM'), and its auto-sectioning matches sections by that exact
    // value. A dropdown whose value isn't among its items throws, so the
    // stored value is offered as-is (never rewritten) alongside the usual
    // choices.
    final courseItems = _withCurrent(
        _courseOptions.skip(1).toList(), widget.editing?.course);
    final yearItems = _withCurrent(
        _yearLevelOptions.skip(1).toList(), widget.editing?.yearLevel);

    return DialogShell(
      title: widget.editing == null ? 'Register Student' : 'Edit Student',
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      width: 720,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const _FormSection(
            icon: Icons.badge_outlined,
            title: 'Student Information',
          ),
          _FormRow(children: [
            _FormCell(
              label: 'RFID No.',
              child: TextField(
                controller: _rfidController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
            _FormCell(
              label: 'Student Number',
              child: TextField(
                controller: _studentNumberController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
          ]),
          const _FormSection(
            icon: Icons.school_outlined,
            title: 'Academic Details',
          ),
          _FormRow(children: [
            _FormCell(
              flex: 3,
              label: 'Course',
              child: DropdownButtonFormField<String>(
                value: _course,
                isExpanded: true,
                icon: dropdownArrowIcon(context),
                style: fieldTextStyle(context),
                dropdownColor: ItTechnicianColors.card(context),
                decoration: fieldDecoration(context),
                items: courseItems
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _course = value),
              ),
            ),
            _FormCell(
              flex: 2,
              label: 'Year Level',
              child: DropdownButtonFormField<String>(
                value: _yearLevel,
                isExpanded: true,
                icon: dropdownArrowIcon(context),
                style: fieldTextStyle(context),
                dropdownColor: ItTechnicianColors.card(context),
                decoration: fieldDecoration(context),
                items: yearItems
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _yearLevel = value),
              ),
            ),
            _FormCell(
              flex: 2,
              label: 'Section',
              child: TextField(
                controller: _sectionController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
          ]),
          const _FormSection(
            icon: Icons.person_outline_rounded,
            title: 'Personal Details',
          ),
          _FormRow(children: [
            _FormCell(
              flex: 3,
              label: 'First Name',
              child: TextField(
                controller: _firstNameController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
            _FormCell(
              flex: 3,
              label: 'Last Name',
              child: TextField(
                controller: _lastNameController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
            _FormCell(
              flex: 1,
              label: 'M.I.',
              child: TextField(
                controller: _middleInitialController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
          ]),
          const _FormSection(
            icon: Icons.family_restroom_outlined,
            title: 'Parent / Guardian',
          ),
          _FormRow(children: [
            _FormCell(
              flex: 3,
              label: 'Parent/Guardian Name',
              child: TextField(
                controller: _guardianController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
            _FormCell(
              flex: 2,
              label: 'Guardian Contact No.',
              child: TextField(
                controller: _guardianContactNoController,
                enabled: !_saving,
                style: fieldTextStyle(context),
                decoration: fieldDecoration(context),
              ),
            ),
          ]),
        ],
      ),
      actions: [
        PaleButton(
          label: 'Cancel',
          onTap: _saving ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        _saving
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

/// A labelled group heading in the Register / Edit Student form.
class _FormSection extends StatelessWidget {
  const _FormSection({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ItTechnicianColors.azureBlue),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 13.5,
              fontWeight: FontWeight.w600,
              color: ItTechnicianColors.rowText(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(height: 1, color: ItTechnicianColors.cardBorder(context)),
          ),
        ],
      ),
    );
  }
}

/// One labelled field of a [_FormRow], sized by [flex] when the row is
/// side by side.
class _FormCell extends StatelessWidget {
  const _FormCell({
    required this.label,
    required this.child,
    this.flex = 1,
  });

  final String label;
  final Widget child;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [FieldLabel(label), child],
    );
  }
}

/// A row of [_FormCell]s: side by side (by their flex) when there is room,
/// stacked into a single column on narrow dialogs/phones.
class _FormRow extends StatelessWidget {
  const _FormRow({required this.children});

  final List<_FormCell> children;

  static const double _gap = 16;
  static const double _stackBelow = 520;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _stackBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  children[i],
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(flex: children[i].flex, child: children[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}
