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
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Some rows could not be imported'),
            content: SingleChildScrollView(
              child: Text(summary.errors.join('\n\n')),
            ),
            actions: [
              SecondaryPillButton(
                label: 'OK',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // A dialog, not a snackbar: ScheduleImportException's message can
        // include a multi-line diagnostic preview of what was actually
        // read from the file (see ScheduleImportRunner._diagnosticPreview)
        // when the format isn't recognized — a snackbar would truncate it.
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Import failed'),
            content: SingleChildScrollView(
              child: SelectableText('$e'),
            ),
            actions: [
              SecondaryPillButton(
                label: 'OK',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
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
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Some meetings could not be assigned a room'),
            content: SingleChildScrollView(
              child: Text(result.unassigned.join('\n\n')),
            ),
            actions: [
              SecondaryPillButton(
                label: 'OK',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Could not auto-generate room assignments'),
            content: SingleChildScrollView(child: SelectableText('$e')),
            actions: [
              SecondaryPillButton(
                label: 'OK',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
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

/// Printable/exportable Room Assignment schedule — the Room Assignment
/// analog of [SectionScheduleCard], except scoped by the page's own school
/// year/term selection rather than a section picker, since a room
/// assignment run covers every section at once. `rows == null` means
/// nothing has loaded yet (before the first generate/refresh); an empty
/// list means loaded but nothing has a room yet.
class _RoomAssignmentScheduleCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasRows = rows != null && rows!.isNotEmpty;
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
                      loading: loading,
                      onTap: loading ? null : onRefresh,
                    ),
                    if (onExportPdf != null && hasRows)
                      SecondaryPillButton(
                        label: 'Export PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        loading: exportingPdf,
                        onTap: exportingPdf ? null : onExportPdf,
                      ),
                    if (onExportExcel != null && hasRows)
                      SecondaryPillButton(
                        label: 'Export Excel',
                        icon: Icons.table_view_outlined,
                        loading: exportingExcel,
                        onTap: exportingExcel ? null : onExportExcel,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (loading && rows == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (rows == null)
            const DashboardTableEmptyState(
              icon: Icons.meeting_room_outlined,
              message: 'Generate room assignments to see them here.',
            )
          else if (rows!.isEmpty)
            const DashboardTableEmptyState(
              icon: Icons.meeting_room_outlined,
              message:
                  'No meetings have a room assigned yet for this school year/term.',
            )
          else
            _RoomAssignmentTable(rows: rows!),
        ],
      ),
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
  DashboardTableColumn('Room', flex: 2),
  DashboardTableColumn('Day', flex: 1),
  DashboardTableColumn('Time', flex: 2),
  DashboardTableColumn('Subject', flex: 3),
  DashboardTableColumn('Section', flex: 2),
  DashboardTableColumn('Instructor', flex: 3),
];

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
                Text(
                  rows[i].room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTablePrimaryStyle(context),
                ),
                body(_roomAssignmentDayLabels[rows[i].day] ?? rows[i].day),
                body(formatClockRange12h(rows[i].startTime, rows[i].endTime)),
                body(rows[i].component == null
                    ? rows[i].subjectTitle
                    : '${rows[i].subjectTitle} (${rows[i].component})'),
                body(rows[i].sectionName),
                body(rows[i].professorName),
              ],
            ),
        ],
      ),
    );
  }
}
