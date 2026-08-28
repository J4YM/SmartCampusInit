import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'registrar_dashboard_page.dart';

// ---------------------------------------------------------------------------
// RFID Management tab — "Student Without RFID" table with bulk selection,
// "View Logs", and "Submit & Notify".
// ---------------------------------------------------------------------------

class RfidManagementView extends StatefulWidget {
  const RfidManagementView({
    super.key,
    required this.students,
    this.onSubmitNotify,
    this.onViewLogs,
  });

  final List<RegistrarStudentModel> students;

  /// Called with the ids of every checked student when "Submit & Notify" is
  /// tapped. Falls back to no-op when omitted (demo behavior).
  final ValueChanged<List<String>>? onSubmitNotify;

  /// Falls back to no-op when omitted (demo behavior — no log history to
  /// show yet).
  final VoidCallback? onViewLogs;

  @override
  State<RfidManagementView> createState() => _RfidManagementViewState();
}

class _RfidManagementViewState extends State<RfidManagementView> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;
  int _currentPage = 1;
  final Set<String> _selectedIds = {};

  bool get _allSelected =>
      widget.students.isNotEmpty &&
      widget.students.every((s) => _selectedIds.contains(s.id));

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(widget.students.map((s) => s.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final students = widget.students;
    final totalPages =
        students.isEmpty ? 1 : (students.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    return Container(
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
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Text(
                  'Student Without RFID',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
                ),
                _PillActionButton(
                  label: 'View Logs',
                  background: RegistrarColors.background(context),
                  foreground: RegistrarColors.azureBlue,
                  onTap: widget.onViewLogs ?? () {},
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: RegistrarColors.navyBlue,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: _allSelected,
                    onChanged: (_) => _toggleSelectAll(),
                    activeColor: RegistrarColors.azureBlue,
                    checkColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                Expanded(flex: 2, child: Text('Student Name', style: headerStyle)),
                Expanded(child: Text('Student ID', style: headerStyle)),
                Expanded(child: Text('Grade & Section', style: headerStyle)),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Status',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
              ],
            ),
          ),
          if (pageStudents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Every enrolled student already has an RFID card',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
              ),
            )
          else
            for (final student in pageStudents)
              _RfidRow(
                student: student,
                isSelected: _selectedIds.contains(student.id),
                onChanged: (checked) => setState(() {
                  checked == true
                      ? _selectedIds.add(student.id)
                      : _selectedIds.remove(student.id);
                }),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (students.isNotEmpty)
                  Text(
                    'Showing ${pageStudents.length} of ${students.length} total students',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 10 : 12,
                      color: RegistrarColors.mutedText(context),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (students.isNotEmpty) ...[
                      _PillActionButton(
                        label: 'Previous',
                        background: RegistrarColors.background(context),
                        foreground: RegistrarColors.azureBlue,
                        onTap: currentPage > 1
                            ? () =>
                                setState(() => _currentPage = currentPage - 1)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _PillActionButton(
                        label: 'Next',
                        background: RegistrarColors.azureBlue,
                        foreground: Colors.white,
                        onTap: currentPage < totalPages
                            ? () =>
                                setState(() => _currentPage = currentPage + 1)
                            : null,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _PillActionButton(
                      label: 'Submit & Notify',
                      background: RegistrarColors.azureBlue,
                      foreground: Colors.white,
                      icon: Icons.mark_email_read_outlined,
                      onTap: _selectedIds.isEmpty
                          ? null
                          : () =>
                              widget.onSubmitNotify?.call(_selectedIds.toList()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RfidRow extends StatelessWidget {
  const _RfidRow({
    required this.student,
    required this.isSelected,
    required this.onChanged,
  });

  final RegistrarStudentModel student;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: RegistrarColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: RegistrarColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Checkbox(
              value: isSelected,
              onChanged: onChanged,
              activeColor: RegistrarColors.azureBlue,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(flex: 2, child: Text(student.name, style: style)),
          Expanded(child: Text(student.studentId, style: style)),
          Expanded(child: Text(student.section, style: style)),
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x33CD4855),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'No RFID',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: RegistrarColors.brightRed,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: disabled ? foreground.withOpacity(0.6) : foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
