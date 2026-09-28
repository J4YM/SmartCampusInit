import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'add_student_dialog.dart';
import 'change_section_dialog.dart';
import 'class_schedule_view.dart' show SectionOption, SubjectOption;
import 'import_students_dialog.dart';
import 'registrar_dashboard_page.dart';
import 'subject_enrollments_view.dart';

// ---------------------------------------------------------------------------
// Student Records tab — master-detail: full Student List + selected
// student's Student Profile panel.
// ---------------------------------------------------------------------------

/// [Expanded] (tight fit) when [bounded] — the ancestor gave this a real
/// height to fill — or [Flexible] (loose fit) when not, since Expanded
/// throws under an unbounded incoming height constraint (mobile/stacked,
/// where the page itself scrolls instead).
Widget _boundedOrFlexible(bool bounded, Widget child) {
  return bounded ? Expanded(child: child) : Flexible(child: child);
}

class StudentRecordsView extends StatefulWidget {
  const StudentRecordsView({
    super.key,
    required this.students,
    required this.selectedStudent,
    required this.onSelect,
    this.onAddStudent,
    this.sectionOptions = const [],
    this.onImportStudents,
    this.onChangeSection,
    this.subjectOptions = const [],
    this.onFetchEnrollments,
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
  });

  final List<RegistrarStudentModel> students;
  final RegistrarStudentModel? selectedStudent;
  final ValueChanged<RegistrarStudentModel> onSelect;

  /// Persists a new student via the same `students`/`profiles` tables IT
  /// Technician's own Student Records tab already reads and writes. Falls
  /// back to no "Add New Student" button at all when omitted (demo
  /// behavior — nowhere to save it).
  final Future<void> Function(NewStudentForm form)? onAddStudent;

  /// Sections the "Edit Student" dialog's section-override picker offers.
  final List<SectionOption> sectionOptions;

  /// Runs a batch enrollment upload — see EnrollmentImportRunner
  /// (lib/data/enrollment_import_runner.dart). Each student's section is
  /// chosen automatically from their own row's Program/Level, so this
  /// takes no section — see ImportStudentsDialog's own doc comment. Falls
  /// back to no "Import Students" button at all when omitted.
  final Future<ImportStudentsResult> Function({
    required PlatformFile file,
  })? onImportStudents;

  /// Persists a section override — see ChangeSectionDialog's own doc
  /// comment. Falls back to no "Change Section" button on the student
  /// profile panel when omitted.
  final Future<void> Function(String studentId, SectionOption section)?
      onChangeSection;

  /// Subjects the "Enroll in Subject" dialog's first picker offers.
  final List<SubjectOption> subjectOptions;

  /// Loads the selected student's active subject enrollments. Falls back
  /// to hiding the whole "Subject Enrollments" section when omitted.
  final Future<List<StudentEnrollmentModel>> Function(String studentId)?
      onFetchEnrollments;

  /// Loads every class_sections offering (any section) for a chosen
  /// subject — the "Enroll in Subject" dialog's second picker.
  final Future<List<ClassSectionOffering>> Function(String subjectId)?
      onFetchOfferings;

  /// Enrolls the student in a chosen offering — the actual "mark this
  /// student irregular for Subject X" action when that offering belongs
  /// to a different section than their own.
  final Future<void> Function(String studentId, String classSectionId)?
      onEnroll;

  /// Drops one of the student's existing enrollments.
  final Future<void> Function(String enrollmentId)? onDrop;

  @override
  State<StudentRecordsView> createState() => _StudentRecordsViewState();
}

class _StudentRecordsViewState extends State<StudentRecordsView> {
  final _searchController = TextEditingController();
  String _query = '';
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  // Checkbox (multi-select) facets — a student matches a facet if it
  // matches *any* checked value, empty means "All". Section/Year check
  // against the block letter / year digit parsed out of the student's
  // compound section string (e.g. "BSIT - 4B"), not the raw string, since
  // the filter's own choices are the fixed A/B/C and 1st-4th sets rather
  // than whatever section strings happen to be on file.
  Set<String> _programFilter = {};
  Set<String> _sectionFilter = {};
  Set<String> _yearFilter = {};
  EnrollmentStatus? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filter hierarchy, top to bottom: Program, Year, Section — each
  /// level's own offered choices are only the ones actually present among
  /// students matching whatever's selected at the level(s) above it (not
  /// below), so picking a Program immediately narrows which Years/Sections
  /// even show up, and picking a Year further narrows Section. Program
  /// itself is unaffected by Year/Section (it's the top of the hierarchy)
  /// so it's always drawn from every student.
  List<String> get _availablePrograms {
    final programs = {for (final s in widget.students) s.program}.toList();
    programs.sort();
    return programs;
  }

  List<String> get _availableYearDigits {
    final candidates = _programFilter.isEmpty
        ? widget.students
        : widget.students.where((s) => _programFilter.contains(s.program));
    final years = <String>{
      for (final s in candidates)
        if (sectionYearDigit(s.section) != null) sectionYearDigit(s.section)!,
    }.toList();
    years.sort();
    return years;
  }

  List<String> get _availableSectionBlocks {
    final candidates = widget.students.where((s) {
      final matchesProgram =
          _programFilter.isEmpty || _programFilter.contains(s.program);
      final matchesYear = _yearFilter.isEmpty ||
          _yearFilter.contains(sectionYearDigit(s.section));
      return matchesProgram && matchesYear;
    });
    final blocks = <String>{
      for (final s in candidates)
        if (sectionBlockLetter(s.section) != null)
          sectionBlockLetter(s.section)!,
    }.toList();
    blocks.sort();
    return blocks;
  }

  /// Drops any Year/Section selections that just fell out of availability
  /// (e.g. Section = C was checked, then Program narrowed to one with no
  /// C sections) — called after every Program/Year change, in hierarchy
  /// order (Year first, since Section's own availability depends on it).
  void _pruneUnavailableSelections() {
    _yearFilter = _yearFilter.intersection(_availableYearDigits.toSet());
    _sectionFilter =
        _sectionFilter.intersection(_availableSectionBlocks.toSet());
  }

  /// Passed to [FilterMenuButton] as a *builder* (called again after every
  /// change made inside its filter panel) rather than a plain list — see
  /// that param's own doc comment for why a plain list can't stay current
  /// while the panel's open. Hierarchy order top to bottom: Program, Year,
  /// Section.
  List<FilterMenuCheckboxSection> _buildCheckboxSections() => [
        FilterMenuCheckboxSection(
          title: 'Program',
          options: [
            for (final program in _availablePrograms)
              FilterMenuOption(label: program, value: program),
          ],
          selectedValues: _programFilter,
          onChanged: (value) => setState(() {
            _programFilter = value;
            _currentPage = 1;
            _pruneUnavailableSelections();
          }),
        ),
        FilterMenuCheckboxSection(
          title: 'Year',
          options: [
            for (final digit in _availableYearDigits)
              FilterMenuOption(label: yearLabelForDigit(digit), value: digit),
          ],
          selectedValues: _yearFilter,
          onChanged: (value) => setState(() {
            _yearFilter = value;
            _currentPage = 1;
            _pruneUnavailableSelections();
          }),
        ),
        FilterMenuCheckboxSection(
          title: 'Section',
          options: [
            for (final block in _availableSectionBlocks)
              FilterMenuOption(label: block, value: block),
          ],
          selectedValues: _sectionFilter,
          onChanged: (value) => setState(() {
            _sectionFilter = value;
            _currentPage = 1;
          }),
        ),
      ];

  List<RegistrarStudentModel> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.students.where((s) {
      final matchesQuery = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.studentId.toLowerCase().contains(query);
      final matchesProgram =
          _programFilter.isEmpty || _programFilter.contains(s.program);
      final matchesSection = _sectionFilter.isEmpty ||
          _sectionFilter.contains(sectionBlockLetter(s.section));
      final matchesYear =
          _yearFilter.isEmpty || _yearFilter.contains(sectionYearDigit(s.section));
      final matchesStatus =
          _statusFilter == null || s.status == _statusFilter;
      return matchesQuery &&
          matchesProgram &&
          matchesSection &&
          matchesYear &&
          matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        final listCard = LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            final table = _StudentListCard(
              students: _filtered,
              selectedStudentId: widget.selectedStudent?.id,
              onSelect: widget.onSelect,
              searchController: _searchController,
              onSearchChanged: (value) => setState(() {
                _query = value;
                _currentPage = 1;
              }),
              currentPage: _currentPage,
              pageSize: _pageSize,
              onPageChanged: (page) => setState(() => _currentPage = page),
              onAddStudent: widget.onAddStudent,
              sectionOptions: widget.sectionOptions,
              onImportStudents: widget.onImportStudents,
              checkboxSectionsBuilder: _buildCheckboxSections,
              statusFilter: _statusFilter,
              onStatusFilterChanged: (value) => setState(() {
                _statusFilter = value;
                _currentPage = 1;
              }),
            );
            return bounded ? table : table;
          },
        );

        final profileCard = _StudentProfileCard(
          student: widget.selectedStudent,
          sectionOptions: widget.sectionOptions,
          onChangeSection: widget.onChangeSection,
          subjectOptions: widget.subjectOptions,
          onFetchEnrollments: widget.onFetchEnrollments,
          onFetchOfferings: widget.onFetchOfferings,
          onEnroll: widget.onEnroll,
          onDrop: widget.onDrop,
        );

        if (stackColumns) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              listCard,
              const SizedBox(height: 18),
              profileCard,
            ],
          );
        }

        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: listCard),
              const SizedBox(width: 18),
              SizedBox(width: 320, child: profileCard),
            ],
          ),
        );
      },
    );
  }
}

/// "Student List" title plus search+filter — stacked on top of each other
/// at mobile width, since the title text and the search field plus filter
/// button don't fit on one line below ~500px.
class _StudentListHeader extends StatelessWidget {
  const _StudentListHeader({
    required this.searchController,
    required this.onSearchChanged,
    this.onAddStudent,
    this.sectionOptions = const [],
    this.onImportStudents,
    required this.checkboxSectionsBuilder,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function(NewStudentForm form)? onAddStudent;
  final List<SectionOption> sectionOptions;
  final Future<ImportStudentsResult> Function({
    required PlatformFile file,
  })? onImportStudents;

  /// Builds the Program/Year/Section checkbox facets — see
  /// [FilterMenuButton.checkboxSections]'s own doc comment for why this is
  /// a builder rather than a plain list.
  final List<FilterMenuCheckboxSection> Function() checkboxSectionsBuilder;
  final EnrollmentStatus? statusFilter;
  final ValueChanged<EnrollmentStatus?> onStatusFilterChanged;

  void _openAddStudentDialog(BuildContext context) {
    final onAddStudent = this.onAddStudent;
    if (onAddStudent == null) return;
    // showDialog inserts its subtree into the root Navigator's Overlay, a
    // sibling of this page's own local Theme — not a descendant of it — so
    // context.isDarkMode inside AddStudentDialog would otherwise see the
    // app's ambient theme instead of this dashboard's actual toggle.
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: AddStudentDialog(onSave: onAddStudent),
      ),
    );
  }

  void _openImportStudentsDialog(BuildContext context) {
    final onImportStudents = this.onImportStudents;
    if (onImportStudents == null) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: ImportStudentsDialog(
          onImport: onImportStudents,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(
      'Student List',
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 16 : 18,
        fontWeight: FontWeight.w600,
        color: RegistrarColors.rowText(context),
      ),
    );
    final addButton = onAddStudent == null
        ? null
        : FilledButton.icon(
            onPressed: () => _openAddStudentDialog(context),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add New Student'),
            style: FilledButton.styleFrom(
              backgroundColor: RegistrarColors.azureBlue,
              // Explicit: the default (colorScheme.onPrimary) turns dark
              // navy under the dark theme, unreadable on this fixed blue.
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
    final importButton = onImportStudents == null
        ? null
        : OutlinedButton.icon(
            onPressed: () => _openImportStudentsDialog(context),
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Import Students'),
            style: OutlinedButton.styleFrom(
              foregroundColor: RegistrarColors.azureBlue,
              side: BorderSide(color: RegistrarColors.cardBorder(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
    final searchAndFilter = Row(
      children: [
        Expanded(
          child: SearchField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(width: 10),
        FilterMenuButton(
          backgroundColor: RegistrarColors.background(context),
          menuColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          iconColor: RegistrarColors.placeholderText(context),
          textColor: RegistrarColors.rowText(context),
          mutedTextColor: RegistrarColors.mutedText(context),
          accentColor: RegistrarColors.azureBlue,
          sections: [
            FilterMenuSection(
              title: 'Status',
              options: const [
                FilterMenuOption(label: 'Active', value: 'active'),
                FilterMenuOption(label: 'Inactive', value: 'inactive'),
              ],
              selectedValue: statusFilter == null
                  ? null
                  : statusFilter == EnrollmentStatus.active
                      ? 'active'
                      : 'inactive',
              onChanged: (value) => onStatusFilterChanged(switch (value) {
                'active' => EnrollmentStatus.active,
                'inactive' => EnrollmentStatus.inactive,
                _ => null,
              }),
            ),
          ],
          checkboxSections: checkboxSectionsBuilder,
        ),
      ],
    );

    if (context.isMobileWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (addButton != null) ...[
            const SizedBox(height: 12),
            addButton,
          ],
          if (importButton != null) ...[
            const SizedBox(height: 12),
            importButton,
          ],
          const SizedBox(height: 12),
          searchAndFilter,
        ],
      );
    }

    // Below ~900px of card width (e.g. a 1024px window, where the detail
    // panel takes the right side) title + both buttons leave no room for
    // the search, so it drops to its own full-width line.
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                title,
                if (addButton != null) addButton,
                if (importButton != null) importButton,
              ],
            ),
            const SizedBox(height: 12),
            searchAndFilter,
          ],
        );
      }
      return Row(
        children: [
          title,
          if (addButton != null) ...[
            const SizedBox(width: 16),
            addButton,
          ],
          if (importButton != null) ...[
            const SizedBox(width: 10),
            importButton,
          ],
          const SizedBox(width: 16),
          // Grows into the free space up to 440px (a fixed 220px, shared
          // with the 107px Filter pill, left the search itself ~100px).
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: searchAndFilter,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _StudentListCard extends StatelessWidget {
  const _StudentListCard({
    required this.students,
    required this.selectedStudentId,
    required this.onSelect,
    required this.searchController,
    required this.onSearchChanged,
    required this.currentPage,
    required this.pageSize,
    required this.onPageChanged,
    this.onAddStudent,
    this.sectionOptions = const [],
    this.onImportStudents,
    required this.checkboxSectionsBuilder,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });

  final List<RegistrarStudentModel> students;
  final String? selectedStudentId;
  final ValueChanged<RegistrarStudentModel> onSelect;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final int currentPage;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(NewStudentForm form)? onAddStudent;
  final List<SectionOption> sectionOptions;
  final Future<ImportStudentsResult> Function({
    required PlatformFile file,
  })? onImportStudents;

  final List<FilterMenuCheckboxSection> Function() checkboxSectionsBuilder;
  final EnrollmentStatus? statusFilter;
  final ValueChanged<EnrollmentStatus?> onStatusFilterChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages =
        students.isEmpty ? 1 : (students.length / pageSize).ceil();
    final page = currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((page - 1) * pageSize).take(pageSize).toList();
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = pageStudents.isEmpty
            ? Center(
                child: Text(
                  'No matching students',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                itemCount: pageStudents.length,
                itemBuilder: (context, index) {
                  final student = pageStudents[index];
                  return InkWell(
                    onTap: () => onSelect(student),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: student.id == selectedStudentId
                            ? RegistrarColors.background(context)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                              color: RegistrarColors.cardBorder(context)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text(student.name,
                                  style: _cellStyle(context))),
                          Expanded(
                              flex: 2,
                              child: Text(student.studentId,
                                  style: _cellStyle(context))),
                          Expanded(
                              flex: 2,
                              child: Text(student.section,
                                  style: _cellStyle(context))),
                          Expanded(
                              child: Text(
                                  student.gpa?.toStringAsFixed(1) ?? '—',
                                  style: _cellStyle(context))),
                          SizedBox(
                            width: 70,
                            child: Center(
                                child: StatusBadge(status: student.status)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

        return BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: _StudentListHeader(
                  searchController: searchController,
                  onSearchChanged: onSearchChanged,
                  onAddStudent: onAddStudent,
                  sectionOptions: sectionOptions,
                  onImportStudents: onImportStudents,
                  checkboxSectionsBuilder: checkboxSectionsBuilder,
                  statusFilter: statusFilter,
                  onStatusFilterChanged: onStatusFilterChanged,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: RegistrarColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(
                        flex: 2, child: Text('Student', style: headerStyle)),
                    Expanded(
                        flex: 2, child: Text('Student ID', style: headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('Grade & Section', style: headerStyle)),
                    Expanded(child: Text('GPA', style: headerStyle)),
                    SizedBox(
                      width: 70,
                      child: Text(
                        'Status',
                        textAlign: TextAlign.center,
                        style: headerStyle,
                      ),
                    ),
                  ],
                ),
              ),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (students.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: PillPaginationFooter(
                    shownCount: pageStudents.length,
                    totalCount: students.length,
                    label: 'total student grade records',
                    canGoPrevious: page > 1,
                    canGoNext: page < totalPages,
                    onPrevious: () => onPageChanged(page - 1),
                    onNext: () => onPageChanged(page + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  TextStyle _cellStyle(BuildContext context) => GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 11 : 13,
        fontWeight: FontWeight.w500,
        color: RegistrarColors.rowText(context),
      );
}

class _StudentProfileCard extends StatelessWidget {
  const _StudentProfileCard({
    required this.student,
    this.sectionOptions = const [],
    this.onChangeSection,
    this.subjectOptions = const [],
    this.onFetchEnrollments,
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
  });

  final RegistrarStudentModel? student;
  final List<SectionOption> sectionOptions;

  /// Persists a section override — see ChangeSectionDialog's own doc
  /// comment. Falls back to no "Change Section" button when omitted.
  final Future<void> Function(String studentId, SectionOption section)?
      onChangeSection;

  final List<SubjectOption> subjectOptions;
  final Future<List<StudentEnrollmentModel>> Function(String studentId)?
      onFetchEnrollments;
  final Future<List<ClassSectionOffering>> Function(String subjectId)?
      onFetchOfferings;
  final Future<void> Function(String studentId, String classSectionId)?
      onEnroll;
  final Future<void> Function(String enrollmentId)? onDrop;

  void _openChangeSectionDialog(BuildContext context) {
    final onChangeSection = this.onChangeSection;
    final student = this.student;
    if (onChangeSection == null || student == null) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: ChangeSectionDialog(
          studentName: student.name,
          currentSectionName: student.section,
          sectionOptions: sectionOptions,
          onSave: (section) => onChangeSection(student.id, section),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;

        return BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Student Profile',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: RegistrarColors.rowText(context),
                      ),
                    ),
                  ),
                  if (onChangeSection != null && student != null)
                    TextButton.icon(
                      onPressed: () => _openChangeSectionDialog(context),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('Change Section'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (student == null)
                _boundedOrFlexible(
                  bounded,
                  Center(
                    child: Text(
                      'Select a student to view their profile',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: RegistrarColors.mutedText(context),
                      ),
                    ),
                  ),
                )
              else
                _boundedOrFlexible(
                  bounded,
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileDetails(student: student!),
                        if (onFetchEnrollments != null)
                          SubjectEnrollmentsSection(
                            key: ValueKey(student!.id),
                            studentId: student!.id,
                            onFetchEnrollments: onFetchEnrollments!,
                            subjectOptions: subjectOptions,
                            onFetchOfferings: onFetchOfferings,
                            onEnroll: onEnroll,
                            onDrop: onDrop,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.student});

  final RegistrarStudentModel student;

  @override
  Widget build(BuildContext context) {
    final initials = student.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: RegistrarColors.azureBlue,
          child: Text(
            initials,
            style: GoogleFonts.poppins(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          student.name,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: RegistrarColors.rowText(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          student.studentId,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: RegistrarColors.rowText(context),
          ),
        ),
        const SizedBox(height: 20),
        Divider(color: RegistrarColors.cardBorder(context)),
        const SizedBox(height: 12),
        _DetailRow(label: 'Program', value: student.program),
        _DetailRow(label: 'Section', value: student.section),
        _DetailRow(label: 'GPA', value: student.gpa?.toStringAsFixed(1) ?? '—'),
        _DetailRow(label: 'Parent/Guardian', value: student.parentGuardian),
        _DetailRow(label: 'Contact No.', value: student.contactNo),
        _DetailRow(label: 'Email', value: student.email),
        _DetailRow(label: 'Enrolled', value: student.enrolledDate),
        _DetailRow(
          label: 'RFID Status',
          value: student.hasRfid ? 'Active' : 'No RFID',
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: RegistrarColors.mutedText(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: RegistrarColors.rowText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
