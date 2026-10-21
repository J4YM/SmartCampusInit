import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'add_student_dialog.dart';
import 'change_section_dialog.dart';
import 'class_schedule_view.dart' show SectionOption, SubjectOption;
import 'edit_student_dialog.dart';
import 'import_students_dialog.dart';
import 'lift_restriction_dialog.dart';
import 'parent_login_dialog.dart';
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
    this.onConfirmEnrollment,
    this.onEditStudent,
    this.onIssueParentLogin,
    this.subjectOptions = const [],
    this.onFetchEnrollments,
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
    this.onDropStudent,
    this.onFetchSanctions,
    this.onLiftRestriction,
  });

  /// Lets an administrator lift an enrollment restriction (reason required).
  /// No button when omitted, which is the case for everyone but an Admin.
  final Future<void> Function(String studentId, String reason)?
      onLiftRestriction;

  /// Loads the selected student's sanctions for the read-only "Disciplinary
  /// record" section of their profile. No section when omitted or empty.
  final Future<List<StudentSanctionEntry>> Function(String studentId)?
      onFetchSanctions;

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

  /// Marks the student as enrolled for the current term, re-activating
  /// their account after an Admin term migration. No button when omitted.
  final Future<void> Function(String studentId)? onConfirmEnrollment;

  /// Persists corrected personal/parent-guardian details — see
  /// EditStudentDialog. Falls back to no "Edit Details" button on the
  /// student profile panel when omitted.
  final Future<void> Function(String studentId, EditStudentForm form)?
      onEditStudent;

  /// Issues the student's linked guardian(s) a new temporary Parent Portal
  /// password and returns it for one-time display/export — see
  /// ParentLoginDialog. No "Parent Portal Login" button when omitted.
  final Future<List<ImportGuardianCredential>> Function(String studentId)?
      onIssueParentLogin;

  /// Subjects the "Enroll in Subject" dialog's first picker offers.
  final List<SubjectOption> subjectOptions;

  /// Loads the selected student's active subject enrollments, shown in the
  /// "View Subjects" popup. Falls back to hiding that button when omitted.
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

  /// Withdraws the whole student: drops every one of their enrollments.
  final Future<void> Function(String studentId)? onDropStudent;

  @override
  State<StudentRecordsView> createState() => _StudentRecordsViewState();
}

class _StudentRecordsViewState extends State<StudentRecordsView> {
  final _searchController = TextEditingController();
  String _query = '';
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  /// The one section picked in the Filter popup (its full section string),
  /// or null for "All sections".
  String? _sectionFilter;
  EnrollmentStatus? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The Filter popup's section list — every section on file, grouped by
  /// year there.
  FilterSectionPicker get _sectionPicker => FilterSectionPicker(
        entries: sectionFilterEntries(
            [for (final s in widget.students) (s.section, s.program)]),
        selectedId: _sectionFilter,
        onChanged: (id) => setState(() {
          _sectionFilter = id;
          _currentPage = 1;
        }),
      );

  List<RegistrarStudentModel> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.students.where((s) {
      final matchesQuery = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.studentId.toLowerCase().contains(query);
      final matchesSection = matchesSectionFilter(_sectionFilter, s.section);
      final matchesStatus =
          _statusFilter == null || s.status == _statusFilter;
      return matchesQuery && matchesSection && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < kMasterDetailStackBreakpoint;

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
              sectionFilter: _sectionPicker,
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
          onConfirmEnrollment: widget.onConfirmEnrollment,
          onFetchSanctions: widget.onFetchSanctions,
          onLiftRestriction: widget.onLiftRestriction,
          onEditStudent: widget.onEditStudent,
          onIssueParentLogin: widget.onIssueParentLogin,
          subjectOptions: widget.subjectOptions,
          onFetchEnrollments: widget.onFetchEnrollments,
          onFetchOfferings: widget.onFetchOfferings,
          onEnroll: widget.onEnroll,
          onDrop: widget.onDrop,
          onDropStudent: widget.onDropStudent,
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

        final cardsRow = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: listCard),
            const SizedBox(width: 18),
            SizedBox(width: 320, child: profileCard),
          ],
        );
        // Bounded = the page is filling the window, so the row simply takes
        // all of it; otherwise fall back to a viewport-based cap.
        if (constraints.hasBoundedHeight) return cardsRow;
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
          child: cardsRow,
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
    required this.sectionFilter,
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

  /// The Filter popup's section list (single section or "All sections").
  final FilterSectionPicker sectionFilter;
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
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
            label: const Text('Add New Student'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, kDashboardControlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
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
        : SecondaryPillButton(
            label: 'Import Students',
            icon: Icons.upload_file_outlined,
            onTap: () => _openImportStudentsDialog(context),
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
          sectionFilter: sectionFilter,
        ),
      ],
    );

    if (context.isMobileWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (importButton != null) ...[
            const SizedBox(height: 12),
            importButton,
          ],
          if (addButton != null) ...[
            const SizedBox(height: 12),
            addButton,
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
            // Title at the far left, search + filter to its right; the two
            // buttons wrap onto their own line below, at the far right.
            Row(
              children: [
                title,
                const SizedBox(width: 16),
                Expanded(child: searchAndFilter),
              ],
            ),
            if (addButton != null || importButton != null) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (importButton != null) importButton,
                  if (addButton != null) addButton,
                ],
              ),
            ],
          ],
        );
      }
      // Title at the far left; search + filter and the two buttons grouped
      // at the far right.
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
                  // Grows into the free space up to 440px, after the buttons
                  // have taken what they need (a fixed 220px, shared with
                  // the 107px Filter pill, left the search itself ~100px).
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: searchAndFilter,
                    ),
                  ),
                  if (importButton != null) ...[
                    const SizedBox(width: 16),
                    importButton,
                  ],
                  if (addButton != null) ...[
                    const SizedBox(width: 10),
                    addButton,
                  ],
                ],
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
    required this.sectionFilter,
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

  final FilterSectionPicker sectionFilter;
  final EnrollmentStatus? statusFilter;
  final ValueChanged<EnrollmentStatus?> onStatusFilterChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages =
        students.isEmpty ? 1 : (students.length / pageSize).ceil();
    final page = currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((page - 1) * pageSize).take(pageSize).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        // A newly registered student drops in at the top of the list.
        final Widget list = DashboardTableRows(
          scrollable: true,
          shrinkWrap: !bounded,
          empty: const DashboardTableEmptyState(message: 'No matching students'),
          rows: [
            for (var index = 0; index < pageStudents.length; index++)
              Builder(
                key: ValueKey('student-record-${pageStudents[index].id}'),
                builder: (context) {
                  final student = pageStudents[index];
                  return DashboardTableRow(
                    columns: _studentListColumns,
                    selected: student.id == selectedStudentId,
                    onTap: () => onSelect(student),
                    showDivider: index < pageStudents.length - 1,
                    cells: [
                      Text(
                        student.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dashboardTablePrimaryStyle(context),
                      ),
                      Text(
                        student.studentId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dashboardTableIdStyle(context),
                      ),
                      Text(
                        student.section,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dashboardTableBodyStyle(context),
                      ),
                      Text(
                        student.gpa?.toStringAsFixed(2) ?? '—',
                        style: dashboardTableBodyStyle(context),
                      ),
                      StatusBadge(status: student.status),
                    ],
                  );
                },
              ),
          ],
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
                  sectionFilter: sectionFilter,
                  statusFilter: statusFilter,
                  onStatusFilterChanged: onStatusFilterChanged,
                ),
              ),
              DashboardTableSection(
                columns: _studentListColumns,
                expandBody: bounded,
                body: list,
              ),
              if (students.isNotEmpty)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: page,
                    totalPages: totalPages,
                    totalCount: students.length,
                    textColor: RegistrarColors.mutedText(context),
                    accentColor: RegistrarColors.azureBlue,
                    mutedBackground: RegistrarColors.background(context),
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
}

const _studentListColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 2, minWidth: 220),
  DashboardTableColumn('Student ID', flex: 2, minWidth: 120),
  DashboardTableColumn('Grade & Section', flex: 2, minWidth: 150),
  DashboardTableColumn('GWA', flex: 1, minWidth: 90),
  DashboardTableColumn('Status', flex: 1, compact: true, minWidth: 110),
];

class _StudentProfileCard extends StatelessWidget {
  const _StudentProfileCard({
    required this.student,
    this.sectionOptions = const [],
    this.onChangeSection,
    this.onConfirmEnrollment,
    this.onEditStudent,
    this.onIssueParentLogin,
    this.subjectOptions = const [],
    this.onFetchEnrollments,
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
    this.onDropStudent,
    this.onFetchSanctions,
    this.onLiftRestriction,
  });

  /// See [StudentRecordsView.onLiftRestriction].
  final Future<void> Function(String studentId, String reason)?
      onLiftRestriction;

  /// See [StudentRecordsView.onFetchSanctions].
  final Future<List<StudentSanctionEntry>> Function(String studentId)?
      onFetchSanctions;

  final RegistrarStudentModel? student;
  final List<SectionOption> sectionOptions;

  /// See [StudentRecordsView.onEditStudent].
  final Future<void> Function(String studentId, EditStudentForm form)?
      onEditStudent;

  /// See [StudentRecordsView.onIssueParentLogin].
  final Future<List<ImportGuardianCredential>> Function(String studentId)?
      onIssueParentLogin;

  /// Persists a section override — see ChangeSectionDialog's own doc
  /// comment. Falls back to no "Change Section" button when omitted.
  final Future<void> Function(String studentId, SectionOption section)?
      onChangeSection;

  /// Marks the student as enrolled for the current term, re-activating
  /// their account after an Admin term migration. No button when omitted.
  final Future<void> Function(String studentId)? onConfirmEnrollment;

  final List<SubjectOption> subjectOptions;
  final Future<List<StudentEnrollmentModel>> Function(String studentId)?
      onFetchEnrollments;
  final Future<List<ClassSectionOffering>> Function(String subjectId)?
      onFetchOfferings;
  final Future<void> Function(String studentId, String classSectionId)?
      onEnroll;
  final Future<void> Function(String enrollmentId)? onDrop;

  /// Withdraws the whole student: drops every one of their enrollments.
  final Future<void> Function(String studentId)? onDropStudent;

  Future<void> _liftRestriction(BuildContext context) async {
    final onLift = onLiftRestriction;
    final student = this.student;
    if (onLift == null || student == null) return;
    final reason = await showAppPopup<String>(
      context: context,
      builder: (_) => LiftRestrictionDialog(studentName: student.name),
    );
    if (reason == null) return;
    await onLift(student.id, reason);
  }

  void _openEditStudentDialog(BuildContext context) {
    final onEditStudent = this.onEditStudent;
    final student = this.student;
    if (onEditStudent == null || student == null) return;
    // Same Theme re-wrap as _openChangeSectionDialog below: showDialog's
    // subtree lives under the root Navigator, outside this card's Theme.
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: EditStudentDialog(student: student, onSave: onEditStudent),
      ),
    );
  }

  void _openParentLoginDialog(BuildContext context) {
    final onIssueParentLogin = this.onIssueParentLogin;
    final student = this.student;
    if (onIssueParentLogin == null || student == null) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: ParentLoginDialog(
          studentName: student.name,
          onIssue: () => onIssueParentLogin(student.id),
        ),
      ),
    );
  }

  /// Re-activating a student is a deliberate step (their portal, kiosk and
  /// professor rosters open up again), so it asks first.
  Future<void> _confirmEnrollmentWithPrompt(BuildContext context) async {
    final onConfirmEnrollment = this.onConfirmEnrollment;
    final student = this.student;
    if (onConfirmEnrollment == null || student == null) return;
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: theme,
        child: AlertDialog(
          key: const Key('confirm-enrollment-dialog'),
          title: const Text('Confirm enrollment?'),
          content: Text(
            'This re-activates ${student.name} (${student.studentId}) for the '
            'current term. They will be able to sign in again and can be '
            'enrolled in classes. Only confirm once their enrollment is '
            'settled.',
          ),
          actions: [
            TextButton(
              key: const Key('confirm-enrollment-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-enrollment-yes'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm Enrollment'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await onConfirmEnrollment(student.id);
  }

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
              Text(
                'Student Profile',
                style: dashboardCardTitleStyle(context,
                    color: RegistrarColors.rowText(context)),
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
                        if (student!.isRestricted) ...[
                          const SizedBox(height: 14),
                          _RestrictionBanner(
                            student: student!,
                            onLift: onLiftRestriction == null
                                ? null
                                : () => _liftRestriction(context),
                          ),
                        ],
                        if (onFetchSanctions != null)
                          _DisciplinaryRecord(
                            key: ValueKey('discipline-${student!.id}'),
                            studentId: student!.id,
                            onFetch: onFetchSanctions!,
                          ),
                        // Sit under the details, spanning the card's full
                        // width.
                        if (onEditStudent != null) ...[
                          const SizedBox(height: 16),
                          RegistrarPillButton(
                            key: const Key('edit-student-details'),
                            label: 'Edit Details',
                            icon: Icons.edit_outlined,
                            expand: true,
                            onTap: () => _openEditStudentDialog(context),
                          ),
                        ],
                        if (onConfirmEnrollment != null &&
                            !student!.isRestricted &&
                            student!.status == EnrollmentStatus.inactive) ...[
                          const SizedBox(height: 16),
                          RegistrarPillButton(
                            key: const Key('confirm-student-enrollment'),
                            label: 'Confirm Enrollment',
                            icon: Icons.how_to_reg_outlined,
                            expand: true,
                            onTap: () => _confirmEnrollmentWithPrompt(context),
                          ),
                        ],
                        if (onIssueParentLogin != null) ...[
                          const SizedBox(height: 16),
                          RegistrarPillButton(
                            key: const Key('issue-parent-login'),
                            label: 'Parent Portal Login',
                            icon: Icons.key_outlined,
                            expand: true,
                            onTap: () => _openParentLoginDialog(context),
                          ),
                        ],
                        if (onChangeSection != null) ...[
                          const SizedBox(height: 16),
                          RegistrarPillButton(
                            label: 'Change Section',
                            icon: Icons.swap_horiz_rounded,
                            expand: true,
                            onTap: () => _openChangeSectionDialog(context),
                          ),
                        ],
                        // The student's subjects (and "Enroll in Subject")
                        // live in a popup so the profile card stays short.
                        if (onFetchEnrollments != null) ...[
                          const SizedBox(height: 16),
                          ViewSubjectsButton(
                            key: ValueKey('view-subjects-${student!.id}'),
                            studentId: student!.id,
                            studentName: student!.name,
                            onFetchEnrollments: onFetchEnrollments!,
                            subjectOptions: subjectOptions,
                            onFetchOfferings: onFetchOfferings,
                            onEnroll: onEnroll,
                            onDrop: onDrop,
                            onDropStudent: onDropStudent,
                          ),
                        ],
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

/// Shown when a Student Affairs sanction bars the student from re-enrolling.
class _RestrictionBanner extends StatelessWidget {
  const _RestrictionBanner({required this.student, this.onLift});

  final RegistrarStudentModel student;

  /// Shown only to an administrator.
  final VoidCallback? onLift;

  @override
  Widget build(BuildContext context) {
    final color = RegistrarColors.dangerRed;
    return Container(
      key: const Key('enrollment-restricted-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.standingLabel,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  'Set by Student Affairs. This student cannot be enrolled '
                  'again until an administrator lifts the restriction.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: RegistrarColors.rowText(context)),
                ),
                if (onLift != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SecondaryPillButton(
                      key: const Key('lift-restriction'),
                      label: 'Lift restriction',
                      icon: Icons.lock_open_rounded,
                      onTap: onLift,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The student's sanctions, read-only. Loads on first build; shows nothing
/// when there are none (or while loading / if the table is unreadable).
class _DisciplinaryRecord extends StatefulWidget {
  const _DisciplinaryRecord({
    super.key,
    required this.studentId,
    required this.onFetch,
  });

  final String studentId;
  final Future<List<StudentSanctionEntry>> Function(String studentId) onFetch;

  @override
  State<_DisciplinaryRecord> createState() => _DisciplinaryRecordState();
}

class _DisciplinaryRecordState extends State<_DisciplinaryRecord> {
  List<StudentSanctionEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.onFetch(widget.studentId);
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      debugPrint('Could not load the disciplinary record: $e');
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disciplinary record',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: RegistrarColors.rowText(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final e in _entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.typeLabel} · ${_months[e.effectiveOn.month - 1]} '
                    '${e.effectiveOn.day}, ${e.effectiveOn.year}',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: e.affectsEnrollment
                          ? RegistrarColors.dangerRed
                          : RegistrarColors.mutedText(context),
                    ),
                  ),
                  Text(
                    e.description,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: RegistrarColors.rowText(context)),
                  ),
                ],
              ),
            ),
        ],
      ),
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
        _DetailRow(label: 'GWA', value: student.gpa?.toStringAsFixed(2) ?? '—'),
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
