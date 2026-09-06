import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data model — swap defaultStudents with Supabase/API data later.
// ---------------------------------------------------------------------------

enum StudentDirectoryStatus {
  active,
  suspended,
  inactive;

  String get label {
    switch (this) {
      case StudentDirectoryStatus.active:
        return 'Active';
      case StudentDirectoryStatus.suspended:
        return 'Suspended';
      case StudentDirectoryStatus.inactive:
        return 'Inactive';
    }
  }
}

class StudentDirectoryModel {
  const StudentDirectoryModel({
    required this.studentId,
    required this.avatarInitials,
    required this.fullName,
    required this.email,
    required this.course,
    required this.yearLevel,
    required this.section,
    required this.rfidCard,
    required this.attendancePercentage,
    required this.violations,
    required this.status,
    required this.avatarColor,
  });

  final String studentId;
  final String avatarInitials;
  final String fullName;
  final String email;
  final String course;
  final String yearLevel;
  final String section;
  final String? rfidCard;
  final int attendancePercentage;
  final int violations;
  final StudentDirectoryStatus status;
  final Color avatarColor;

  String get courseYearLabel => '$course · $yearLevel Year';
}

// ---------------------------------------------------------------------------
// Default dataset — swap with repository/API calls when backend is ready.
// ---------------------------------------------------------------------------

const defaultStudents = <StudentDirectoryModel>[];

const _courseFilters = ['All Courses', 'BSIT', 'BSTM', 'BSBA', 'BSHM'];
const _yearFilters = ['All Years', '1st', '2nd', '3rd', '4th'];

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _DirectoryColors {
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color cardBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0x0DE2E8F0);
  // Shared brand accent (the same blue every other dashboard's buttons use)
  // — stays constant across themes, like every other dashboard's own accent.
  static const primaryButton = Color(0xFF345892);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static Color rowHover(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF8FAFC);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class StudentDirectoryPage extends StatefulWidget {
  const StudentDirectoryPage({
    super.key,
    required this.students,
    this.onAddStudent,
    this.onView,
    this.onEdit,
    this.onDelete,
    this.isLoading = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount,
    this.onPreviousPage,
    this.onNextPage,
    this.onCourseFilterChanged,
    this.onYearFilterChanged,
  });

  factory StudentDirectoryPage.empty({Key? key}) {
    return StudentDirectoryPage(key: key, students: defaultStudents);
  }

  final List<StudentDirectoryModel> students;

  /// Falls back to a "tapped" snackbar when omitted (demo behavior).
  final VoidCallback? onAddStudent;
  final ValueChanged<StudentDirectoryModel>? onView;
  final ValueChanged<StudentDirectoryModel>? onEdit;
  final ValueChanged<StudentDirectoryModel>? onDelete;

  /// Notified alongside the dropdown's own local state, so a connected page
  /// can re-query the server for this filter (paginated results only cover
  /// one page at a time, so filtering has to happen server-side to see
  /// matches outside the currently loaded page). Values are this widget's
  /// own filter labels ("All Courses"/"BSIT"/… and "All Years"/"1st"/…).
  final ValueChanged<String>? onCourseFilterChanged;
  final ValueChanged<String>? onYearFilterChanged;

  /// True while a parent-level page fetch is in flight — renders skeleton
  /// rows instead of freezing on an unchanged table.
  final bool isLoading;

  /// Pagination state, supplied by a connected page that fetches one page
  /// of students at a time instead of the whole directory at once. The
  /// footer only renders when [totalPages] > 1 or a page-change callback is
  /// supplied.
  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  State<StudentDirectoryPage> createState() => _StudentDirectoryPageState();
}

class _StudentDirectoryPageState extends State<StudentDirectoryPage> {
  final _searchController = TextEditingController();
  String _selectedCourse = _courseFilters.first;
  String _selectedYear = _yearFilters.first;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StudentDirectoryModel> get _filteredStudents {
    final query = _searchController.text.trim().toLowerCase();
    return widget.students.where((student) {
      final matchesSearch = query.isEmpty ||
          student.fullName.toLowerCase().contains(query) ||
          student.studentId.toLowerCase().contains(query);
      final matchesCourse =
          _selectedCourse == 'All Courses' || student.course == _selectedCourse;
      final matchesYear =
          _selectedYear == 'All Years' || student.yearLevel == _selectedYear;
      return matchesSearch && matchesCourse && matchesYear;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = _filteredStudents;

    return ColoredBox(
      color: _DirectoryColors.background(context),
      child: SafeArea(
        // The scroll view spans the full content pane (no width cap out
        // here) so its scrollbar sits at the pane's true edge; only the
        // inner content is capped at 1440px and centered.
        child: SingleChildScrollView(
          child: DashboardPageWrapper(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Student Directory',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _DirectoryColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Browse and manage enrolled student records',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w400,
                    color: _DirectoryColors.secondaryText(context),
                  ),
                ),
                const SizedBox(height: 24),
                _ControlBar(
                  searchController: _searchController,
                  selectedCourse: _selectedCourse,
                  selectedYear: _selectedYear,
                  onSearchChanged: (_) => setState(() {}),
                  onCourseChanged: (value) {
                    final course = value ?? _courseFilters.first;
                    setState(() => _selectedCourse = course);
                    widget.onCourseFilterChanged?.call(course);
                  },
                  onYearChanged: (value) {
                    final year = value ?? _yearFilters.first;
                    setState(() => _selectedYear = year);
                    widget.onYearFilterChanged?.call(year);
                  },
                  onAddStudent: widget.onAddStudent ??
                      () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Add Student tapped',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                ),
                const SizedBox(height: 16),
                _StudentTableCard(
                  students: filteredStudents,
                  isLoading: widget.isLoading,
                  onView: widget.onView,
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                ),
                if (widget.totalPages > 1 ||
                    widget.onPreviousPage != null ||
                    widget.onNextPage != null) ...[
                  const SizedBox(height: 12),
                  _PaginationFooter(
                    currentPage: widget.currentPage,
                    totalPages: widget.totalPages,
                    totalCount: widget.totalCount,
                    isLoading: widget.isLoading,
                    onPrevious: widget.onPreviousPage,
                    onNext: widget.onNextPage,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pagination footer
// ---------------------------------------------------------------------------

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.isLoading,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final bool isLoading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          totalCount == null
              ? 'Page $currentPage of $totalPages'
              : 'Page $currentPage of $totalPages · $totalCount total',
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 10 : 12,
            color: _DirectoryColors.secondaryText(context),
          ),
        ),
        Row(
          children: [
            PaginationPillButton(
              label: 'Previous',
              background: _DirectoryColors.background(context),
              foreground: _DirectoryColors.primaryButton,
              onTap: (isLoading || currentPage <= 1) ? null : onPrevious,
            ),
            const SizedBox(width: 8),
            PaginationPillButton(
              label: 'Next',
              background: _DirectoryColors.primaryButton,
              foreground: Colors.white,
              onTap:
                  (isLoading || currentPage >= totalPages) ? null : onNext,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Control bar
// ---------------------------------------------------------------------------

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.searchController,
    required this.selectedCourse,
    required this.selectedYear,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onYearChanged,
    required this.onAddStudent,
  });

  final TextEditingController searchController;
  final String selectedCourse;
  final String selectedYear;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onYearChanged;
  final VoidCallback onAddStudent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: searchController,
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _FilterDropdown(
                      value: selectedCourse,
                      items: _courseFilters,
                      onChanged: onCourseChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FilterDropdown(
                      value: selectedYear,
                      items: _yearFilters,
                      onChanged: onYearChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AddStudentButton(onPressed: onAddStudent),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              flex: 3,
              child: _SearchField(
                controller: searchController,
                onChanged: onSearchChanged,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 160,
              child: _FilterDropdown(
                value: selectedCourse,
                items: _courseFilters,
                onChanged: onCourseChanged,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: _FilterDropdown(
                value: selectedYear,
                items: _yearFilters,
                onChanged: onYearChanged,
              ),
            ),
            const SizedBox(width: 16),
            _AddStudentButton(onPressed: onAddStudent),
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 12 : 14,
        color: _DirectoryColors.primaryText(context),
      ),
      decoration: InputDecoration(
        hintText: 'Search by name or ID...',
        hintStyle: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 12 : 14,
          color: _DirectoryColors.secondaryText(context),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: _DirectoryColors.secondaryText(context),
        ),
        filled: true,
        fillColor: _DirectoryColors.card(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _DirectoryColors.cardBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _DirectoryColors.cardBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _DirectoryColors.primaryButton),
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      isExpanded: true,
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 12 : 14,
        color: _DirectoryColors.primaryText(context),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: _DirectoryColors.card(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _DirectoryColors.cardBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _DirectoryColors.cardBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _DirectoryColors.primaryButton),
        ),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            ),
          )
          .toList(),
    );
  }
}

class _AddStudentButton extends StatelessWidget {
  const _AddStudentButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(
        'Add Student',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 12 : 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _DirectoryColors.primaryButton,
        foregroundColor: _DirectoryColors.primaryButtonText,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data table
// ---------------------------------------------------------------------------

class _StudentTableCard extends StatelessWidget {
  const _StudentTableCard({
    required this.students,
    this.isLoading = false,
    this.onView,
    this.onEdit,
    this.onDelete,
  });

  final List<StudentDirectoryModel> students;
  final bool isLoading;
  final ValueChanged<StudentDirectoryModel>? onView;
  final ValueChanged<StudentDirectoryModel>? onEdit;
  final ValueChanged<StudentDirectoryModel>? onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _DirectoryColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _DirectoryColors.cardBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TableHeaderRow(),
            // Bounded by pagination (a fixed page size), so a shrink-wrapped,
            // non-scrolling list here is safe — the page's own outer scroll
            // handles reaching the rest of the page instead of this card
            // trapping its own scrollbar.
            isLoading && students.isEmpty
                ? const _SkeletonTableBody(rowCount: 8)
                : students.isEmpty
                    ? const _EmptyTableState(
                        icon: Icons.search_off_rounded,
                        message: 'No records found',
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          return _StudentTableRow(
                            student: students[index],
                            showDivider: index < students.length - 1,
                            onView: onView,
                            onEdit: onEdit,
                            onDelete: onDelete,
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading placeholder
// ---------------------------------------------------------------------------

class _SkeletonTableBody extends StatefulWidget {
  const _SkeletonTableBody({required this.rowCount});

  final int rowCount;

  @override
  State<_SkeletonTableBody> createState() => _SkeletonTableBodyState();
}

class _SkeletonTableBodyState extends State<_SkeletonTableBody>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final _opacity = Tween<double>(begin: 0.4, end: 0.9).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.rowCount,
          itemBuilder: (context, index) =>
              _SkeletonRow(opacity: _opacity.value),
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.opacity});

  final double opacity;

  static const _flexValues = _DirectoryTableLayout.columnFlex;

  Widget _bar({double widthFactor = 0.7}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0).withOpacity(opacity),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _DirectoryColors.cardBorder(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _DirectoryTableLayout.horizontalPadding,
          vertical: 16,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _flexValues.length; i++)
              Expanded(
                flex: _flexValues[i],
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == _flexValues.length - 1
                        ? 0
                        : _DirectoryTableLayout.columnGap,
                  ),
                  child: _bar(widthFactor: i == 1 ? 0.9 : 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTableState extends StatelessWidget {
  const _EmptyTableState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 12 : 14,
                fontWeight: FontWeight.w500,
                color: _DirectoryColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

abstract final class _DirectoryTableLayout {
  // STUDENT ID, NAME, COURSE/YEAR, SECTION, RFID CARD, ATTENDANCE,
  // VIOLATIONS, STATUS, ACTIONS — tuned so VIOLATIONS/STATUS never crowd.
  static const columnFlex = <int>[3, 4, 3, 2, 3, 3, 2, 2, 2];
  static const compactColumnIndexes = <int>{3, 7};
  static const horizontalPadding = 16.0;
  static const headerVerticalPadding = 14.0;
  static const columnGap = 8.0;
  static const rowVerticalPadding = 12.0;
  static const rowMinHeight = 64.0;
}

TextStyle _tableHeaderStyle(BuildContext context) {
  return GoogleFonts.poppins(
    fontSize: context.isMobileWidth ? 9 : 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: _DirectoryColors.secondaryText(context),
  );
}

TextStyle _tableIdStyle(BuildContext context, {Color? color, FontWeight? weight}) {
  return GoogleFonts.poppins(
    fontSize: context.isMobileWidth ? 10 : 12,
    fontWeight: weight ?? FontWeight.w600,
    letterSpacing: 0.2,
    color: color ?? _DirectoryColors.primaryText(context),
  );
}

TextStyle _tableMonoBodyStyle(BuildContext context, {Color? color}) {
  return GoogleFonts.poppins(
    fontSize: context.isMobileWidth ? 9 : 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
    color: color ?? _DirectoryColors.secondaryText(context),
  );
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.flex,
    required this.child,
    required this.isLast,
    this.compact = false,
  });

  final int flex;
  final Widget child;
  final bool isLast;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(
          right: isLast ? 0 : _DirectoryTableLayout.columnGap,
        ),
        child: compact
            ? Align(alignment: Alignment.centerLeft, child: child)
            : Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: child,
              ),
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const headers = [
      'STUDENT ID',
      'NAME',
      'COURSE / YEAR',
      'SECTION',
      'RFID CARD',
      'ATTENDANCE',
      'VIOLATIONS',
      'STATUS',
      'ACTIONS',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: _DirectoryTableLayout.horizontalPadding,
        vertical: _DirectoryTableLayout.headerVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: _DirectoryColors.card(context),
        border: Border(
          bottom: BorderSide(color: _DirectoryColors.cardBorder(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < headers.length; i++)
            _TableCell(
              flex: _DirectoryTableLayout.columnFlex[i],
              isLast: i == headers.length - 1,
              compact: _DirectoryTableLayout.compactColumnIndexes.contains(i),
              child: Text(
                headers[i],
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: _tableHeaderStyle(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _StudentTableRow extends StatelessWidget {
  const _StudentTableRow({
    required this.student,
    required this.showDivider,
    this.onView,
    this.onEdit,
    this.onDelete,
  });

  final StudentDirectoryModel student;
  final bool showDivider;
  final ValueChanged<StudentDirectoryModel>? onView;
  final ValueChanged<StudentDirectoryModel>? onEdit;
  final ValueChanged<StudentDirectoryModel>? onDelete;

  @override
  Widget build(BuildContext context) {
    const flexValues = _DirectoryTableLayout.columnFlex;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: _DirectoryColors.rowHover(context),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        mouseCursor: SystemMouseCursors.click,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(color: _DirectoryColors.cardBorder(context)),
                  )
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: _DirectoryTableLayout.rowMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _DirectoryTableLayout.horizontalPadding,
                vertical: _DirectoryTableLayout.rowVerticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _TableCell(
                    flex: flexValues[0],
                    isLast: false,
                    child: Text(
                      student.studentId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _tableIdStyle(context),
                    ),
                  ),
                  _TableCell(
                    flex: flexValues[1],
                    isLast: false,
                    child: Row(
                      children: [
                        _InitialAvatar(
                          initials: student.avatarInitials,
                          color: student.avatarColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                student.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: context.isMobileWidth ? 11 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: _DirectoryColors.primaryText(context),
                                ),
                              ),
                              Text(
                                student.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: context.isMobileWidth ? 9 : 11,
                                  fontWeight: FontWeight.w400,
                                  color: _DirectoryColors.secondaryText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TableCell(
                    flex: flexValues[2],
                    isLast: false,
                    child: Text(
                      student.courseYearLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 10 : 12,
                        color: _DirectoryColors.secondaryText(context),
                      ),
                    ),
                  ),
                  _TableCell(
                    flex: flexValues[3],
                    isLast: false,
                    compact: true,
                    child: _SectionBadge(section: student.section),
                  ),
                  _TableCell(
                    flex: flexValues[4],
                    isLast: false,
                    child: _RfidCell(rfidCard: student.rfidCard),
                  ),
                  _TableCell(
                    flex: flexValues[5],
                    isLast: false,
                    child: _AttendanceCell(
                        percentage: student.attendancePercentage),
                  ),
                  _TableCell(
                    flex: flexValues[6],
                    isLast: false,
                    child: _ViolationsCell(count: student.violations),
                  ),
                  _TableCell(
                    flex: flexValues[7],
                    isLast: false,
                    compact: true,
                    child: _StatusBadge(status: student.status),
                  ),
                  _TableCell(
                    flex: flexValues[8],
                    isLast: true,
                    child: _ActionButtons(
                      student: student,
                      onView: onView,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.initials,
    required this.color,
  });

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 9 : 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  const _SectionBadge({required this.section});

  final String section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? const Color(0xFF111111)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _DirectoryColors.cardBorder(context)),
      ),
      child: Text(
        section,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: _DirectoryColors.primaryText(context),
        ),
      ),
    );
  }
}

class _RfidCell extends StatelessWidget {
  const _RfidCell({required this.rfidCard});

  final String? rfidCard;

  @override
  Widget build(BuildContext context) {
    if (rfidCard != null) {
      return Text(
        rfidCard!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _tableMonoBodyStyle(context),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: Color(0xFFEA580C),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Unassigned',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 9 : 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFEA580C),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttendanceCell extends StatelessWidget {
  const _AttendanceCell({required this.percentage});

  final int percentage;

  Color get _barColor {
    if (percentage > 90) return const Color(0xFF22C55E);
    if (percentage >= 75) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 6,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(_barColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$percentage%',
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 9 : 11,
            fontWeight: FontWeight.w600,
            color: _DirectoryColors.primaryText(context),
          ),
        ),
      ],
    );
  }
}

class _ViolationsCell extends StatelessWidget {
  const _ViolationsCell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$count',
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 11 : 13,
        fontWeight: FontWeight.w700,
        color: count > 0
            ? const Color(0xFFEF4444)
            : _DirectoryColors.secondaryText(context),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final StudentDirectoryStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      StudentDirectoryStatus.active => (
          const Color(0xFFDCFCE7),
          const Color(0xFF15803D),
        ),
      StudentDirectoryStatus.suspended => (
          const Color(0xFFFEE2E2),
          const Color(0xFFDC2626),
        ),
      StudentDirectoryStatus.inactive => (
          const Color(0xFFF1F5F9),
          const Color(0xFF64748B),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.label,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.visible,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 9 : 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.student,
    this.onView,
    this.onEdit,
    this.onDelete,
  });

  final StudentDirectoryModel student;
  final ValueChanged<StudentDirectoryModel>? onView;
  final ValueChanged<StudentDirectoryModel>? onEdit;
  final ValueChanged<StudentDirectoryModel>? onDelete;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionIconButton(
            icon: Icons.visibility_outlined,
            tooltip: 'View student',
            onPressed: onView != null
                ? () => onView!(student)
                : () =>
                    _showActionSnackBar(context, 'View ${student.fullName}'),
          ),
          const SizedBox(width: 8),
          _ActionIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit student',
            onPressed: onEdit != null
                ? () => onEdit!(student)
                : () =>
                    _showActionSnackBar(context, 'Edit ${student.fullName}'),
          ),
          const SizedBox(width: 8),
          _ActionIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete student',
            onPressed: onDelete != null
                ? () => onDelete!(student)
                : () =>
                    _showActionSnackBar(context, 'Delete ${student.fullName}'),
          ),
        ],
      ),
    );
  }

  void _showActionSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      textStyle: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 10 : 12,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: IconButton(
          onPressed: onPressed,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(
            width: 36,
            height: 36,
          ),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            fixedSize: const Size(36, 36),
            hoverColor: const Color(0xFFE2E8F0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(
            icon,
            size: 20,
            color: _DirectoryColors.secondaryText(context),
          ),
        ),
      ),
    );
  }
}
