import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show LogoutConfirmationDialog;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/scheduling_officer_colors.dart';

/// Result of one file upload, for the toast the connected page shows —
/// mirrors ScheduleImportSummary's shape without this presentation-only
/// package depending on the app's own data layer.
class SchedulingOfficerUploadResult {
  const SchedulingOfficerUploadResult({
    required this.offeringsCommitted,
    required this.meetingsCommitted,
    required this.errors,
  });

  final int offeringsCommitted;
  final int meetingsCommitted;
  final List<String> errors;
}

/// Result of one "Auto-Generate Room Assignments" run — mirrors
/// RoomAssignmentSummary's shape without this presentation-only package
/// depending on the app's own data layer.
class RoomAssignmentUiResult {
  const RoomAssignmentUiResult({
    required this.assigned,
    required this.unassigned,
    required this.totalConsidered,
  });

  final int assigned;
  final List<String> unassigned;

  /// 0 means there was nothing left to assign (every meeting already has a
  /// real room) — the UI reads this as "nothing to do", not a failure.
  final int totalConsidered;
}

/// One row of the generated Room Assignment schedule — mirrors
/// RoomAssignmentEntry's shape (lib/data/room_assignment_repository.dart)
/// without this presentation-only package depending on the app's own data
/// layer, matching SectionScheduleRowModel's own convention.
class RoomAssignmentRowModel {
  const RoomAssignmentRowModel({
    required this.classSectionId,
    this.subjectCode,
    required this.subjectTitle,
    this.component,
    required this.sectionName,
    required this.professorName,
    required this.room,
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  /// Groups a subject's Lecture/Laboratory components back together — a
  /// subject with both produces two rows sharing one classSectionId.
  final String classSectionId;
  final String? subjectCode;
  final String subjectTitle;

  /// 'Lecture', 'Laboratory', or null when the subject has no split.
  final String? component;

  final String sectionName;
  final String professorName;
  final String room;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'.
  final String day;

  /// 24-hour "HH:MM".
  final String startTime;
  final String endTime;
}

/// Single-page dashboard for the Scheduling Officer: a readiness banner
/// (has the Registrar uploaded the Classes+Professor list yet?), a school
/// year/term selector, and two upload buttons — Faculty Loading (CFL) and
/// Room Schedule. Deliberately not a multi-tab shell like the other staff
/// dashboards; this role has exactly one job.
class SchedulingOfficerDashboardPage extends StatefulWidget {
  const SchedulingOfficerDashboardPage({
    super.key,
    required this.officerName,
    this.onSignOut,
    required this.existingOfferingsCount,
    this.initialSchoolYear = '',
    this.initialTerm = '1st Semester',
    this.onSchoolYearOrTermChanged,
    this.onUploadFacultyLoading,
    this.onAutoGenerateRooms,
    this.onLoadRoomAssignments,
    this.onExportRoomAssignmentPdf,
    this.onExportRoomAssignmentExcel,
    this.sectionScheduleOptions = const [],
    this.onSectionScheduleSelected,
    this.onExportSectionSchedulePdf,
    this.onExportSectionScheduleExcel,
  });

  final String officerName;
  final VoidCallback? onSignOut;

  /// Number of `subjects` rows already on file (global — not scoped to a
  /// school year/term, since the Classes+Professor list doesn't carry one
  /// at the subjects/profiles level) — null while that count is loading.
  /// Zero means the Registrar hasn't uploaded the Classes+Professor list
  /// yet.
  final int? existingOfferingsCount;

  final String initialSchoolYear;
  final String initialTerm;

  /// Fired whenever the school year field or term dropdown changes, so the
  /// connected page can use the current selection for the next upload
  /// (this does not affect [existingOfferingsCount], which isn't scoped to
  /// a school year/term).
  final void Function(String schoolYear, String term)?
      onSchoolYearOrTermChanged;

  /// Called with the picked CFL file's bytes plus the currently selected
  /// school year/term. Null disables the button (e.g. Supabase not
  /// configured).
  final Future<SchedulingOfficerUploadResult> Function({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  })? onUploadFacultyLoading;

  /// Auto-generates room assignments for every meeting still marked 'TBA'
  /// (uploaded by Faculty Loading with no room on that row) for the
  /// currently selected school year/term — replaces the old manual "Room
  /// Schedule" file upload. Null disables the button (e.g. Supabase not
  /// configured).
  final Future<RoomAssignmentUiResult> Function({
    required String schoolYear,
    required String term,
  })? onAutoGenerateRooms;

  /// Fetches every meeting that already has a real room for the currently
  /// selected school year/term — the printable/exportable Room Assignment
  /// schedule, same role [onSectionScheduleSelected] plays for "Per Section
  /// Schedule". Null disables the whole card.
  final Future<List<RoomAssignmentRowModel>> Function({
    required String schoolYear,
    required String term,
  })? onLoadRoomAssignments;

  /// Exports the currently-shown Room Assignment schedule as a PDF.
  final Future<void> Function(
    String schoolYear,
    String term,
    List<RoomAssignmentRowModel> rows,
  )? onExportRoomAssignmentPdf;

  /// Exports the currently-shown Room Assignment schedule as an editable
  /// spreadsheet.
  final Future<void> Function(
    String schoolYear,
    String term,
    List<RoomAssignmentRowModel> rows,
  )? onExportRoomAssignmentExcel;

  /// (id, name) pairs backing the generated-schedule section picker shown
  /// below the upload cards — lets the Scheduling Officer immediately
  /// verify what an upload just committed.
  final List<({String id, String name})> sectionScheduleOptions;

  /// Fetches every meeting for the picked section's id.
  final Future<List<SectionScheduleRowModel>> Function(String sectionId)?
      onSectionScheduleSelected;

  /// Exports the currently-shown section's generated schedule as a PDF.
  final Future<void> Function(String sectionName, List<SectionScheduleRowModel> rows)?
      onExportSectionSchedulePdf;

  /// Exports the currently-shown section's generated schedule as an
  /// editable spreadsheet.
  final Future<void> Function(String sectionName, List<SectionScheduleRowModel> rows)?
      onExportSectionScheduleExcel;

  @override
  State<SchedulingOfficerDashboardPage> createState() =>
      _SchedulingOfficerDashboardPageState();
}

class _SchedulingOfficerDashboardPageState
    extends State<SchedulingOfficerDashboardPage> {
  late final TextEditingController _schoolYearController;
  late String _term;
  bool _uploadingFacultyLoading = false;
  bool _assigningRooms = false;

  List<RoomAssignmentRowModel>? _roomAssignmentRows;
  bool _loadingRoomAssignments = false;
  bool _exportingRoomAssignmentPdf = false;
  bool _exportingRoomAssignmentExcel = false;

  /// Local to this page, same as every other dashboard's own header toggle
  /// — there is no app-wide dark mode setting.
  final _themeMode = ValueNotifier(ThemeMode.light);

  @override
  void initState() {
    super.initState();
    _schoolYearController = TextEditingController(text: widget.initialSchoolYear);
    _term = widget.initialTerm;
    if (widget.onLoadRoomAssignments != null) _loadRoomAssignmentSchedule();
  }

  @override
  void dispose() {
    _schoolYearController.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  void _notifySchoolYearOrTermChanged() {
    widget.onSchoolYearOrTermChanged?.call(
      _schoolYearController.text.trim(),
      _term,
    );
  }

  void _confirmLogout() {
    final onSignOut = widget.onSignOut;
    if (onSignOut == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          // This State's own `context` sits above the Theme built in
          // build() below, so it can't be used for isDarkMode here — read
          // the toggle's own value directly instead.
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            onSignOut();
          },
        );
      },
    );
  }

  Future<void> _pickAndUpload({
    required Future<SchedulingOfficerUploadResult> Function({
      required Uint8List bytes,
      required String schoolYear,
      required String term,
    }) onUpload,
    required void Function(bool) setBusy,
  }) async {
    final schoolYear = _schoolYearController.text.trim();
    if (schoolYear.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a school year first.')),
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    final picked = result?.files.single;
    final bytes = picked?.bytes;
    if (bytes == null) return;

    setBusy(true);
    try {
      final summary = await onUpload(
        bytes: bytes,
        schoolYear: schoolYear,
        term: _term,
      );
      if (!mounted) return;
      final parts = [
        '${summary.offeringsCommitted} offering(s) imported',
        if (summary.meetingsCommitted > 0)
          '${summary.meetingsCommitted} meeting(s) scheduled',
        if (summary.errors.isNotEmpty) '${summary.errors.length} skipped',
      ];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(parts.join(', '))));
      if (summary.errors.isNotEmpty) {
        showAppMessage(
          context,
          title: 'Some rows could not be imported',
          message: summary.errors.join('\n\n'),
        );
      }
    } catch (e) {
      if (mounted) {
        // A dialog, not a snackbar: ScheduleImportException's message can
        // include a multi-line diagnostic preview of what was actually
        // read from the file (see ScheduleImportRunner._diagnosticPreview)
        // when the format isn't recognized — a snackbar would truncate it.
        showAppMessage(
          context,
          title: 'Import failed',
          message: '$e',
          selectable: true,
        );
      }
    } finally {
      if (mounted) setBusy(false);
    }
  }

  Future<void> _runAutoAssignRooms() async {
    final onAutoGenerateRooms = widget.onAutoGenerateRooms;
    if (onAutoGenerateRooms == null || _assigningRooms) return;
    final schoolYear = _schoolYearController.text.trim();
    if (schoolYear.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a school year first.')),
      );
      return;
    }

    setState(() => _assigningRooms = true);
    try {
      final result = await onAutoGenerateRooms(schoolYear: schoolYear, term: _term);
      if (!mounted) return;
      if (result.totalConsidered == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nothing to assign — every meeting for this school year/term '
              'already has a room.',
            ),
          ),
        );
        return;
      }
      final parts = [
        '${result.assigned} room(s) assigned',
        if (result.unassigned.isNotEmpty) '${result.unassigned.length} could not be placed',
      ];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(parts.join(', '))));
      if (result.assigned > 0) _loadRoomAssignmentSchedule();
      if (result.unassigned.isNotEmpty) {
        showAppMessage(
          context,
          title: 'Some meetings could not be assigned a room',
          message: result.unassigned.join('\n\n'),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppMessage(
          context,
          title: 'Could not auto-generate room assignments',
          message: '$e',
          selectable: true,
        );
      }
    } finally {
      if (mounted) setState(() => _assigningRooms = false);
    }
  }

  Future<void> _loadRoomAssignmentSchedule() async {
    final onLoadRoomAssignments = widget.onLoadRoomAssignments;
    if (onLoadRoomAssignments == null) return;
    final schoolYear = _schoolYearController.text.trim();
    if (schoolYear.isEmpty) return;
    setState(() => _loadingRoomAssignments = true);
    try {
      final rows = await onLoadRoomAssignments(schoolYear: schoolYear, term: _term);
      if (mounted) setState(() => _roomAssignmentRows = rows);
    } finally {
      if (mounted) setState(() => _loadingRoomAssignments = false);
    }
  }

  Future<void> _handleExportRoomAssignmentPdf() async {
    final onExport = widget.onExportRoomAssignmentPdf;
    final rows = _roomAssignmentRows;
    if (onExport == null || rows == null) return;
    setState(() => _exportingRoomAssignmentPdf = true);
    try {
      await onExport(_schoolYearController.text.trim(), _term, rows);
    } finally {
      if (mounted) setState(() => _exportingRoomAssignmentPdf = false);
    }
  }

  Future<void> _handleExportRoomAssignmentExcel() async {
    final onExport = widget.onExportRoomAssignmentExcel;
    final rows = _roomAssignmentRows;
    if (onExport == null || rows == null) return;
    setState(() => _exportingRoomAssignmentExcel = true);
    try {
      await onExport(_schoolYearController.text.trim(), _term, rows);
    } finally {
      if (mounted) setState(() => _exportingRoomAssignmentExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: SchedulingOfficerColors.navyBlue,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ).withPoppins(),
          child: child!,
        );
      },
      // A Builder here hands the subtree a context nested under the Theme
      // built above, so SchedulingOfficerColors.* lookups (which key off
      // context.isDarkMode) see the live toggle instead of whatever theme
      // sits above this whole page.
      child: Builder(
        builder: (context) => _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final isDarkMode = _themeMode.value == ThemeMode.dark;
    return Scaffold(
      backgroundColor: SchedulingOfficerColors.background(context),
      body: Column(
        children: [
          AppHeaderNavBar(
            title: 'Scheduling Officer',
            subtitle: kSchoolName,
            backgroundColor: SchedulingOfficerColors.navyBlue,
            // No onTap: this dashboard is a single page with no tabs, so
            // there is no "home" destination for the logo to return to
            // (see SchoolLogo's own doc comment for this exact case).
            leading: const SchoolLogo(),
            actions: [
              HeaderIconButton(
                icon: isDarkMode
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
                onTap: () {
                  _themeMode.value =
                      isDarkMode ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              if (widget.onSignOut != null)
                HeaderIconButton(
                  icon: Icons.logout_rounded,
                  tooltip: 'Sign Out',
                  onTap: _confirmLogout,
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: DashboardPageWrapper(
                // Same 1440px-capped frame as every other dashboard (16px
                // side padding on mobile, 24px on desktop).
                maxWidth: 1440,
                padding: EdgeInsets.symmetric(
                  horizontal: context.isMobileWidth ? 16 : 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReadinessBanner(count: widget.existingOfferingsCount),
                    const SizedBox(height: 16),
                    _SchoolYearTermCard(
                      schoolYearController: _schoolYearController,
                      term: _term,
                      onSchoolYearChanged: (_) => _notifySchoolYearOrTermChanged(),
                      onTermChanged: (value) {
                        setState(() => _term = value);
                        _notifySchoolYearOrTermChanged();
                      },
                    ),
                    const SizedBox(height: 16),
                    _UploadCard(
                      title: 'Faculty Loading',
                      description: 'Confirmation of Faculty Loading (CFL) — '
                          'one file per professor, with section/room/day/'
                          'time for every subject they teach.',
                      busy: _uploadingFacultyLoading,
                      onTap: widget.onUploadFacultyLoading == null
                          ? null
                          : () => _pickAndUpload(
                                onUpload: widget.onUploadFacultyLoading!,
                                setBusy: (v) =>
                                    setState(() => _uploadingFacultyLoading = v),
                              ),
                    ),
                    const SizedBox(height: 12),
                    _AutoAssignRoomsCard(
                      busy: _assigningRooms,
                      onTap: widget.onAutoGenerateRooms == null
                          ? null
                          : _runAutoAssignRooms,
                    ),
                    if (widget.onLoadRoomAssignments != null) ...[
                      const SizedBox(height: 16),
                      _RoomAssignmentScheduleCard(
                        rows: _roomAssignmentRows,
                        loading: _loadingRoomAssignments,
                        exportingPdf: _exportingRoomAssignmentPdf,
                        exportingExcel: _exportingRoomAssignmentExcel,
                        onRefresh: _loadRoomAssignmentSchedule,
                        onExportPdf: widget.onExportRoomAssignmentPdf == null
                            ? null
                            : _handleExportRoomAssignmentPdf,
                        onExportExcel: widget.onExportRoomAssignmentExcel == null
                            ? null
                            : _handleExportRoomAssignmentExcel,
                      ),
                    ],
                    const SizedBox(height: 16),
                    SectionScheduleCard(
                      sectionOptions: widget.sectionScheduleOptions,
                      onSectionSelected: widget.onSectionScheduleSelected,
                      onExportPdf: widget.onExportSectionSchedulePdf,
                      onExportExcel: widget.onExportSectionScheduleExcel,
                      accentColor: SchedulingOfficerColors.azureBlue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadinessBanner extends StatelessWidget {
  const _ReadinessBanner({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final loading = count == null;
    final ready = (count ?? 0) > 0;
    final color = loading
        ? SchedulingOfficerColors.mutedText(context)
        : ready
            ? SchedulingOfficerColors.successGreen
            : SchedulingOfficerColors.warningAmber;
    final message = loading
        ? 'Checking whether the Registrar has uploaded assignments…'
        : ready
            ? 'Registrar has uploaded $count subject(s) — ready for '
                'Faculty Loading upload / room auto-assignment.'
            : 'No subjects/professors uploaded yet — ask the Registrar to '
                'upload the Classes+Professor list first.';
    return BentoCard(
      backgroundColor: color.withOpacity(0.08),
      borderColor: color.withOpacity(0.3),
      elevated: false,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            loading
                ? Icons.hourglass_top_rounded
                : ready
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: SchedulingOfficerColors.rowText(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchoolYearTermCard extends StatelessWidget {
  const _SchoolYearTermCard({
    required this.schoolYearController,
    required this.term,
    required this.onSchoolYearChanged,
    required this.onTermChanged,
  });

  final TextEditingController schoolYearController;
  final String term;
  final ValueChanged<String> onSchoolYearChanged;
  final ValueChanged<String> onTermChanged;

  /// Plain, borderless filled decoration — no `labelText`, since a
  /// floating label on an `OutlineInputBorder` (even with `borderSide:
  /// none`) still positions itself straddling the field's top edge
  /// (notch math). The label is a static [Text] rendered above the field
  /// instead — matches Discipline Officer's Settings tab convention
  /// (`_SettingsSectionCard(title: ..., child: TextField(hintText: ...))`).
  InputDecoration _fieldDecoration(BuildContext context, {String? hintText}) {
    return InputDecoration(
      isDense: true,
      constraints: const BoxConstraints.tightFor(height: kDashboardControlHeight),
      hintText: hintText,
      hintStyle: GoogleFonts.poppins(
        fontSize: 13,
        color: SchedulingOfficerColors.mutedText(context),
      ),
      filled: true,
      fillColor: SchedulingOfficerColors.fieldFill(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: SchedulingOfficerColors.mutedText(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.poppins(
      fontSize: 13,
      color: SchedulingOfficerColors.rowText(context),
    );
    return BentoCard(
      backgroundColor: SchedulingOfficerColors.card(context),
      borderColor: SchedulingOfficerColors.cardBorder(context),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel(context, 'School Year'),
                TextField(
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.center,
                  controller: schoolYearController,
                  onChanged: onSchoolYearChanged,
                  style: textStyle,
                  decoration: _fieldDecoration(context, hintText: 'e.g. 2026-2027'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel(context, 'Term'),
                DashboardDropdown<String>(
                  value: term,
                  fillColor: SchedulingOfficerColors.fieldFill(context),
                  borderRadius: 8,
                  horizontalPadding: 14,
                  textStyle: textStyle,
                  menuColor: SchedulingOfficerColors.card(context),
                  items: const [
                    DropdownMenuItem(value: '1st Semester', child: Text('1st Semester')),
                    DropdownMenuItem(value: '2nd Semester', child: Text('2nd Semester')),
                  ],
                  onChanged: (value) {
                    if (value != null) onTermChanged(value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.title,
    required this.description,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: SchedulingOfficerColors.card(context),
      borderColor: SchedulingOfficerColors.cardBorder(context),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: SchedulingOfficerColors.rowText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: SchedulingOfficerColors.mutedText(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('Upload'),
              style: FilledButton.styleFrom(
                backgroundColor: SchedulingOfficerColors.azureBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, kDashboardControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Auto-Generate Room Assignments" action card — replaces the old manual
/// "Room Schedule" file upload. Same layout as [_UploadCard] (title,
/// description, trailing button/spinner) but a plain button press instead
/// of a file picker.
class _AutoAssignRoomsCard extends StatelessWidget {
  const _AutoAssignRoomsCard({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: SchedulingOfficerColors.card(context),
      borderColor: SchedulingOfficerColors.cardBorder(context),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room Assignment',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: SchedulingOfficerColors.rowText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Automatically assigns a room to every meeting Faculty '
                  'Loading left unassigned, matching room type (Lecture/'
                  'Laboratory) and capacity, with no double-booking.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: SchedulingOfficerColors.mutedText(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Generate'),
              style: FilledButton.styleFrom(
                backgroundColor: SchedulingOfficerColors.azureBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, kDashboardControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Groups [rows] by room, preserving the order rooms first appear in (the
/// repository already returns them room-sorted) — shared by the card below
/// and mirrors groupRoomAssignmentsByRoom's own grouping in
/// room_assignment_pdf.dart, kept separate since this package can't depend
/// on the host app's document-building code.
Map<String, List<RoomAssignmentRowModel>> _groupRoomAssignmentsByRoom(
  List<RoomAssignmentRowModel> rows,
) {
  final byRoom = <String, List<RoomAssignmentRowModel>>{};
  for (final row in rows) {
    (byRoom[row.room] ??= []).add(row);
  }
  return byRoom;
}

/// Printable/exportable Room Assignment schedule — the Room Assignment
/// analog of [SectionScheduleCard], except scoped by the page's own school
/// year/term selection rather than a section picker (a room assignment run
/// covers every section at once), and grouped one collapsible section per
/// room instead of one flat list — the school's own "ROOM SCHEDULE"
/// workbook is one sheet per room, and a single run can easily cover 20+
/// rooms, so an un-grouped table was an endless scroll to reach the
/// bottom. The room list itself is also paginated for the same reason.
/// `rows == null` means nothing has loaded yet (before the first generate/
/// refresh); an empty list means loaded but nothing has a room yet.
class _RoomAssignmentScheduleCard extends StatefulWidget {
  const _RoomAssignmentScheduleCard({
    required this.rows,
    required this.loading,
    required this.exportingPdf,
    required this.exportingExcel,
    required this.onRefresh,
    required this.onExportPdf,
    required this.onExportExcel,
  });

  final List<RoomAssignmentRowModel>? rows;
  final bool loading;
  final bool exportingPdf;
  final bool exportingExcel;
  final VoidCallback onRefresh;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportExcel;

  @override
  State<_RoomAssignmentScheduleCard> createState() =>
      _RoomAssignmentScheduleCardState();
}

class _RoomAssignmentScheduleCardState
    extends State<_RoomAssignmentScheduleCard> {
  int _currentPage = 1;
  final _expandedRooms = <String>{};

  @override
  void didUpdateWidget(covariant _RoomAssignmentScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh generate/refresh can change which rooms exist entirely —
    // stale page/expansion state from the previous list would be
    // confusing (e.g. "page 3 of 1").
    if (!identical(oldWidget.rows, widget.rows)) {
      _currentPage = 1;
      _expandedRooms.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final hasRows = rows != null && rows.isNotEmpty;
    final byRoom = rows == null ? null : _groupRoomAssignmentsByRoom(rows);
    final roomEntries = byRoom?.entries.toList() ?? const [];
    final pageSize = context.cardPageSize;
    final totalPages = roomEntries.isEmpty ? 1 : (roomEntries.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageEntries =
        roomEntries.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    return BentoCard(
      backgroundColor: SchedulingOfficerColors.card(context),
      borderColor: SchedulingOfficerColors.cardBorder(context),
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Room Assignment Schedule',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SchedulingOfficerColors.rowText(context),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SecondaryPillButton(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      loading: widget.loading,
                      onTap: widget.loading ? null : widget.onRefresh,
                    ),
                    if (widget.onExportPdf != null && hasRows)
                      SecondaryPillButton(
                        label: 'Export PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        loading: widget.exportingPdf,
                        onTap: widget.exportingPdf ? null : widget.onExportPdf,
                      ),
                    if (widget.onExportExcel != null && hasRows)
                      SecondaryPillButton(
                        label: 'Export Excel',
                        icon: Icons.table_view_outlined,
                        loading: widget.exportingExcel,
                        onTap: widget.exportingExcel ? null : widget.onExportExcel,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.loading && rows == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (rows == null)
            const DashboardTableEmptyState(
              icon: Icons.meeting_room_outlined,
              message: 'Generate room assignments to see them here.',
            )
          else if (rows.isEmpty)
            const DashboardTableEmptyState(
              icon: Icons.meeting_room_outlined,
              message:
                  'No meetings have a room assigned yet for this school year/term.',
            )
          else ...[
            for (final entry in pageEntries)
              _RoomGroupSection(
                room: entry.key,
                rows: entry.value,
                expanded: _expandedRooms.contains(entry.key),
                onToggle: () => setState(() {
                  if (!_expandedRooms.add(entry.key)) {
                    _expandedRooms.remove(entry.key);
                  }
                }),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: CardPaginationFooter(
                currentPage: currentPage,
                totalPages: totalPages,
                totalCount: roomEntries.length,
                textColor: SchedulingOfficerColors.mutedText(context),
                accentColor: SchedulingOfficerColors.azureBlue,
                mutedBackground: SchedulingOfficerColors.card(context),
                onPrevious: () => setState(() => _currentPage = currentPage - 1),
                onNext: () => setState(() => _currentPage = currentPage + 1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One room's collapsible section — header (room name, meeting count,
/// expand/collapse chevron) plus, when expanded, that room's meetings as a
/// compact table. Collapsed by default (see [_RoomAssignmentScheduleCardState]),
/// so opening the card doesn't immediately dump every room's full schedule
/// on screen at once.
class _RoomGroupSection extends StatelessWidget {
  const _RoomGroupSection({
    required this.room,
    required this.rows,
    required this.expanded,
    required this.onToggle,
  });

  final String room;
  final List<RoomAssignmentRowModel> rows;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: SchedulingOfficerColors.cardBorder(context)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 20,
                  color: SchedulingOfficerColors.mutedText(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    room,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SchedulingOfficerColors.rowText(context),
                    ),
                  ),
                ),
                Text(
                  '${rows.length} meeting${rows.length == 1 ? '' : 's'}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: SchedulingOfficerColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) _RoomAssignmentTable(rows: rows),
      ],
    );
  }
}

const _roomAssignmentDayLabels = {
  'M': 'Mon',
  'T': 'Tue',
  'W': 'Wed',
  'TH': 'Thu',
  'F': 'Fri',
  'S': 'Sat',
};

const _roomAssignmentColumns = <DashboardTableColumn>[
  DashboardTableColumn('Day', flex: 1),
  DashboardTableColumn('Time', flex: 2),
  DashboardTableColumn('Subject', flex: 3),
  DashboardTableColumn('Section', flex: 2),
  DashboardTableColumn('Instructor', flex: 3),
];

/// One room's meetings — the Room column is dropped since the enclosing
/// [_RoomGroupSection] header already names the room.
class _RoomAssignmentTable extends StatelessWidget {
  const _RoomAssignmentTable({required this.rows});

  final List<RoomAssignmentRowModel> rows;

  @override
  Widget build(BuildContext context) {
    Text body(String text) => Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        );

    return DashboardTableScrollFrame(
      columns: _roomAssignmentColumns,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardTableHeader(
              columns: _roomAssignmentColumns, topBorder: true),
          for (var i = 0; i < rows.length; i++)
            DashboardTableRow(
              columns: _roomAssignmentColumns,
              showDivider: i < rows.length - 1,
              cells: [
                body(_roomAssignmentDayLabels[rows[i].day] ?? rows[i].day),
                body(formatClockRange12h(rows[i].startTime, rows[i].endTime)),
                Text(
                  rows[i].component == null
                      ? rows[i].subjectTitle
                      : '${rows[i].subjectTitle} (${rows[i].component})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTablePrimaryStyle(context),
                ),
                body(rows[i].sectionName),
                body(rows[i].professorName),
              ],
            ),
        ],
      ),
    );
  }
}
