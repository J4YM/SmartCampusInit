import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'add_student_dialog.dart';
import 'registrar_dashboard_page.dart';

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
  });

  final List<RegistrarStudentModel> students;
  final RegistrarStudentModel? selectedStudent;
  final ValueChanged<RegistrarStudentModel> onSelect;

  /// Persists a new student via the same `students`/`profiles` tables IT
  /// Technician's own Student Records tab already reads and writes. Falls
  /// back to no "Add New Student" button at all when omitted (demo
  /// behavior — nowhere to save it).
  final Future<void> Function(NewStudentForm form)? onAddStudent;

  @override
  State<StudentRecordsView> createState() => _StudentRecordsViewState();
}

class _StudentRecordsViewState extends State<StudentRecordsView> {
  final _searchController = TextEditingController();
  String _query = '';
  int get _pageSize => context.isMobileWidth ? 10 : 20;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RegistrarStudentModel> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.students;
    return widget.students
        .where((s) =>
            s.name.toLowerCase().contains(query) ||
            s.studentId.toLowerCase().contains(query))
        .toList();
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
            );
            return bounded ? table : table;
          },
        );

        final profileCard = _StudentProfileCard(student: widget.selectedStudent);

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
/// at mobile width, since the title text and the 220px-wide search field
/// plus filter button don't fit on one line below ~500px.
class _StudentListHeader extends StatelessWidget {
  const _StudentListHeader({
    required this.searchController,
    required this.onSearchChanged,
    this.onAddStudent,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function(NewStudentForm form)? onAddStudent;

  void _openAddStudentDialog(BuildContext context) {
    final onAddStudent = this.onAddStudent;
    if (onAddStudent == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => AddStudentDialog(onSave: onAddStudent),
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
        const FilterButton(),
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
        const Spacer(),
        SizedBox(width: 220, child: searchAndFilter),
      ],
    );
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

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
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
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: RegistrarColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('Student', style: headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('Student ID', style: headerStyle)),
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
  const _StudentProfileCard({required this.student});

  final RegistrarStudentModel? student;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Student Profile',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
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
                      child: _ProfileDetails(student: student!),
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
        _DetailRow(
            label: 'GPA', value: student.gpa?.toStringAsFixed(1) ?? '—'),
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
