import 'package:flutter/material.dart';

import '../rfid_student_row.dart';

/// RFID Management dashboard UI from the Capstone UI repository.
class RfidDashboardPage extends StatefulWidget {
  const RfidDashboardPage({
    super.key,
    required this.students,
    required this.onRefresh,
    required this.onSave,
    required this.onDelete,
    required this.onNotify,
    this.onReturnToHub,
    this.loading = false,
    this.busy = false,
    this.bannerWidgets = const [],
    this.requireGuardian = true,
  });

  final List<RfidStudentRow> students;
  final Future<void> Function() onRefresh;
  final Future<void> Function(
      RfidRegistrationForm form, RfidStudentRow? editing) onSave;
  final Future<void> Function(RfidStudentRow student) onDelete;
  final void Function(String message) onNotify;
  final VoidCallback? onReturnToHub;
  final bool loading;
  final bool busy;
  final List<Widget> bannerWidgets;
  final bool requireGuardian;

  @override
  State<RfidDashboardPage> createState() => _RfidDashboardPageState();
}

class _RfidDashboardPageState extends State<RfidDashboardPage> {
  String? _selectedCourse;
  String? _selectedYearLevel;
  String _searchQuery = '';
  RfidStudentRow? _editingStudent;

  final _rfidNoController = TextEditingController();
  final _studentNumberController = TextEditingController();
  final _sectionController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _guardianController = TextEditingController();
  final _searchController = TextEditingController();

  List<RfidStudentRow> get _studentRecords => widget.students;

  static const List<String> _courseOptions = [
    'BS Business Administration',
    'BS Hospitality Management',
    'BS Information Technology',
    'BS Tourism Management',
  ];

  static const List<String> _yearLevelOptions = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
  ];

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF9CA3AF),
        fontSize: 14,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFF3B82F6)),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF111827),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _textField({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: _fieldDecoration(hint: hint),
        ),
      ],
    );
  }

  List<RfidStudentRow> get _filteredRecords {
    if (_searchQuery.trim().isEmpty) return _studentRecords;
    final q = _searchQuery.toLowerCase();
    return _studentRecords.where((student) {
      return student.rfidNo.toLowerCase().contains(q) ||
          student.studentNumber.toLowerCase().contains(q) ||
          student.fullName.toLowerCase().contains(q) ||
          student.course.toLowerCase().contains(q) ||
          student.yearLevel.toLowerCase().contains(q) ||
          student.section.toLowerCase().contains(q) ||
          student.guardianName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _registerStudent() async {
    if (widget.busy) return;

    final rfidNo = _rfidNoController.text.trim();
    final studentNumber = _studentNumberController.text.trim();
    final section = _sectionController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final middleInitial = _middleInitialController.text.trim();
    final guardianName = _guardianController.text.trim();
    final course = _selectedCourse;
    final yearLevel = _selectedYearLevel;

    if (rfidNo.isEmpty ||
        studentNumber.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        section.isEmpty ||
        (widget.requireGuardian && guardianName.isEmpty) ||
        course == null ||
        yearLevel == null) {
      widget.onNotify(
        'Please complete all required fields before register.',
      );
      return;
    }

    await widget.onSave(
      RfidRegistrationForm(
        rfidNo: rfidNo,
        studentNumber: studentNumber,
        firstName: firstName,
        middleInitial: middleInitial,
        lastName: lastName,
        course: course,
        yearLevel: yearLevel,
        section: section,
        guardianName: guardianName,
      ),
      _editingStudent,
    );

    if (!mounted) return;
    setState(() {
      _clearRegistrationFields();
      _editingStudent = null;
    });
  }

  Future<void> _deleteStudent(RfidStudentRow student) async {
    if (widget.busy) return;
    await widget.onDelete(student);
    if (!mounted) return;
    if (_editingStudent?.id == student.id) {
      setState(() {
        _clearRegistrationFields();
        _editingStudent = null;
      });
    }
  }

  void _startEditStudent(RfidStudentRow student) {
    setState(() {
      _editingStudent = student;
      _rfidNoController.text = student.rfidNo;
      _studentNumberController.text = student.studentNumber;
      _firstNameController.text = student.firstName;
      _middleInitialController.text = student.middleInitial;
      _lastNameController.text = student.lastName;
      _selectedCourse = student.course;
      _selectedYearLevel = student.yearLevel;
      _sectionController.text = student.section;
      _guardianController.text = student.guardianName;
    });
  }

  void _clearRegistrationFields() {
    _rfidNoController.clear();
    _studentNumberController.clear();
    _sectionController.clear();
    _firstNameController.clear();
    _lastNameController.clear();
    _middleInitialController.clear();
    _guardianController.clear();
    _selectedCourse = null;
    _selectedYearLevel = null;
  }

  @override
  void dispose() {
    _rfidNoController.dispose();
    _studentNumberController.dispose();
    _sectionController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _guardianController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            height: 56,
            color: const Color(0xFF15253F),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1480),
                    child: Row(
                      children: [
                        if (widget.onReturnToHub != null) ...[
                          IconButton(
                            tooltip: 'Back to Admin Hub',
                            onPressed: widget.onReturnToHub,
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Icon(
                          Icons.credit_card_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'RFID Management Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1480),
                    child: Column(
                      children: [
                        ...widget.bannerWidgets,
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x07000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Register New Student',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFD1D5DB),
                                    style: BorderStyle.solid,
                                  ),
                                  color: const Color(0xFFFCFCFD),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'RFID No:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _rfidNoController,
                                        style: const TextStyle(fontSize: 14),
                                        decoration: _fieldDecoration(
                                          hint: 'Waiting for RFID scan...',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 960;
                                  return Column(
                                    children: [
                                      if (compact) ...[
                                        _textField(
                                          label: 'Student Number',
                                          hint: 'Enter student number',
                                          controller: _studentNumberController,
                                        ),
                                        const SizedBox(height: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _label('Course'),
                                            DropdownButtonFormField<String>(
                                              value: _selectedCourse,
                                              isExpanded: true,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF111827),
                                              ),
                                              decoration: _fieldDecoration(
                                                hint: 'Select course',
                                              ),
                                              items: _courseOptions
                                                  .map(
                                                    (course) =>
                                                        DropdownMenuItem<
                                                            String>(
                                                      value: course,
                                                      child: Text(
                                                        course,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                setState(
                                                  () => _selectedCourse = value,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _label('Year Level'),
                                            DropdownButtonFormField<String>(
                                              value: _selectedYearLevel,
                                              isExpanded: true,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF111827),
                                              ),
                                              decoration: _fieldDecoration(
                                                hint: 'Select year level',
                                              ),
                                              items: _yearLevelOptions
                                                  .map(
                                                    (year) => DropdownMenuItem<
                                                        String>(
                                                      value: year,
                                                      child: Text(
                                                        year,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                setState(
                                                  () => _selectedYearLevel =
                                                      value,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        _textField(
                                          label: 'Section',
                                          hint: 'Enter section',
                                          controller: _sectionController,
                                        ),
                                      ] else
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _textField(
                                                label: 'Student Number',
                                                hint: 'Enter student number',
                                                controller:
                                                    _studentNumberController,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _label('Course'),
                                                  DropdownButtonFormField<
                                                      String>(
                                                    value: _selectedCourse,
                                                    isExpanded: true,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Color(0xFF111827),
                                                    ),
                                                    decoration:
                                                        _fieldDecoration(
                                                      hint: 'Select course',
                                                    ),
                                                    items: _courseOptions
                                                        .map(
                                                          (course) =>
                                                              DropdownMenuItem<
                                                                  String>(
                                                            value: course,
                                                            child: Text(
                                                              course,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                    onChanged: (value) {
                                                      setState(
                                                        () => _selectedCourse =
                                                            value,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _label('Year Level'),
                                                  DropdownButtonFormField<
                                                      String>(
                                                    value: _selectedYearLevel,
                                                    isExpanded: true,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Color(0xFF111827),
                                                    ),
                                                    decoration:
                                                        _fieldDecoration(
                                                      hint: 'Select year level',
                                                    ),
                                                    items: _yearLevelOptions
                                                        .map(
                                                          (year) =>
                                                              DropdownMenuItem<
                                                                  String>(
                                                            value: year,
                                                            child: Text(
                                                              year,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                    onChanged: (value) {
                                                      setState(
                                                        () =>
                                                            _selectedYearLevel =
                                                                value,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _textField(
                                                label: 'Section',
                                                hint: 'Enter section',
                                                controller: _sectionController,
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 12),
                                      if (compact) ...[
                                        _textField(
                                          label: 'First Name',
                                          hint: 'Enter first name',
                                          controller: _firstNameController,
                                        ),
                                        const SizedBox(height: 12),
                                        _textField(
                                          label: 'Last Name',
                                          hint: 'Enter last name',
                                          controller: _lastNameController,
                                        ),
                                        const SizedBox(height: 12),
                                        _textField(
                                          label: 'M.I.',
                                          hint: 'M.I.',
                                          controller: _middleInitialController,
                                        ),
                                      ] else
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: _textField(
                                                label: 'First Name',
                                                hint: 'Enter first name',
                                                controller:
                                                    _firstNameController,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              flex: 5,
                                              child: _textField(
                                                label: 'Last Name',
                                                hint: 'Enter last name',
                                                controller: _lastNameController,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              flex: 2,
                                              child: _textField(
                                                label: 'M.I.',
                                                hint: 'M.I.',
                                                controller:
                                                    _middleInitialController,
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 12),
                                      _textField(
                                        label: 'Parent/ Guardian Name',
                                        hint: 'Enter guardian name',
                                        controller: _guardianController,
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed:
                                        widget.busy ? null : _registerStudent,
                                    icon: Icon(
                                      _editingStudent == null
                                          ? Icons.add
                                          : Icons.save_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _editingStudent == null
                                          ? 'Register Student'
                                          : 'Save Changes',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF3F4F6),
                                      foregroundColor: const Color(0xFF374151),
                                      elevation: 0,
                                      textStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                    ),
                                  ),
                                  if (_editingStudent != null) ...[
                                    const SizedBox(width: 10),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _editingStudent = null;
                                          _clearRegistrationFields();
                                        });
                                      },
                                      child: const Text('Cancel Edit'),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x07000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Student Records',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 240,
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: (value) {
                                        setState(() => _searchQuery = value);
                                      },
                                      style: const TextStyle(fontSize: 14),
                                      decoration: _fieldDecoration(
                                        hint: 'Search students...',
                                      ).copyWith(
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          size: 18,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (widget.loading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                )
                              else if (_filteredRecords.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                    child: Text(
                                      _studentRecords.isEmpty
                                          ? 'No students loaded yet.'
                                          : 'No students match your search.',
                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: constraints.maxWidth,
                                        ),
                                        child: DataTable(
                                          headingTextStyle: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF111827),
                                          ),
                                          dataTextStyle: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF374151),
                                          ),
                                          columns: const [
                                            DataColumn(label: Text('RFID No.')),
                                            DataColumn(
                                              label: Text('Student Number'),
                                            ),
                                            DataColumn(
                                                label: Text('Full Name')),
                                            DataColumn(label: Text('Course')),
                                            DataColumn(
                                                label: Text('Year Level')),
                                            DataColumn(label: Text('Section')),
                                            DataColumn(
                                              label: Text('Parent/ Guardian'),
                                            ),
                                            DataColumn(label: Text('Actions')),
                                          ],
                                          rows: _filteredRecords
                                              .map(
                                                (student) => DataRow(
                                                  cells: [
                                                    DataCell(
                                                      Text(student.rfidNo),
                                                    ),
                                                    DataCell(
                                                      Text(student
                                                          .studentNumber),
                                                    ),
                                                    DataCell(
                                                      Text(student.fullName),
                                                    ),
                                                    DataCell(
                                                      Text(student.course),
                                                    ),
                                                    DataCell(
                                                      Text(student.yearLevel),
                                                    ),
                                                    DataCell(
                                                      Text(student.section),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                          student.guardianName),
                                                    ),
                                                    DataCell(
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          IconButton(
                                                            tooltip:
                                                                'Edit student',
                                                            icon: const Icon(
                                                              Icons
                                                                  .edit_outlined,
                                                            ),
                                                            onPressed: () =>
                                                                _startEditStudent(
                                                              student,
                                                            ),
                                                          ),
                                                          IconButton(
                                                            tooltip:
                                                                'Delete student',
                                                            icon: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              color: Color(
                                                                0xFFDC2626,
                                                              ),
                                                            ),
                                                            onPressed:
                                                                widget.busy
                                                                    ? null
                                                                    : () {
                                                                        _deleteStudent(
                                                                          student,
                                                                        );
                                                                      },
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
                                    );
                                  },
                                ),
                              const SizedBox(height: 20),
                              Text(
                                'Total Students: ${_studentRecords.length}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '© 2026 RFID Management System. All rights reserved.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
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
