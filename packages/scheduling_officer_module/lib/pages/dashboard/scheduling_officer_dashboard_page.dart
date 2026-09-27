import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
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
    this.onUploadRoomSchedule,
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

  /// Same contract as [onUploadFacultyLoading], for the Room Schedule file.
  final Future<SchedulingOfficerUploadResult> Function({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  })? onUploadRoomSchedule;

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
  bool _uploadingRoomSchedule = false;

  @override
  void initState() {
    super.initState();
    _schoolYearController = TextEditingController(text: widget.initialSchoolYear);
    _term = widget.initialTerm;
  }

  @override
  void dispose() {
    _schoolYearController.dispose();
    super.dispose();
  }

  void _notifySchoolYearOrTermChanged() {
    widget.onSchoolYearOrTermChanged?.call(
      _schoolYearController.text.trim(),
      _term,
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
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
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
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SchedulingOfficerColors.background(context),
      body: Column(
        children: [
          AppHeaderNavBar(
            title: 'Scheduling Officer',
            subtitle: widget.officerName,
            backgroundColor: SchedulingOfficerColors.navyBlue,
            actions: [
              if (widget.onSignOut != null)
                HeaderIconButton(
                  icon: Icons.logout_rounded,
                  tooltip: 'Sign Out',
                  onTap: widget.onSignOut!,
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: DashboardPageWrapper(
                maxWidth: 720,
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
                    _UploadCard(
                      title: 'Room Schedule',
                      description: 'One file per room, listing every subject '
                          'meeting held there with day/time, instructor, '
                          'and section.',
                      busy: _uploadingRoomSchedule,
                      onTap: widget.onUploadRoomSchedule == null
                          ? null
                          : () => _pickAndUpload(
                                onUpload: widget.onUploadRoomSchedule!,
                                setBusy: (v) =>
                                    setState(() => _uploadingRoomSchedule = v),
                              ),
                    ),
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
                'Faculty Loading / Room Schedule upload.'
            : 'No subjects/professors uploaded yet — ask the Registrar to '
                'upload the Classes+Professor list first.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SchedulingOfficerColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SchedulingOfficerColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: schoolYearController,
              onChanged: onSchoolYearChanged,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'School Year (e.g. 2026-2027)',
                labelStyle: GoogleFonts.poppins(fontSize: 12),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: term,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SchedulingOfficerColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SchedulingOfficerColors.cardBorder(context)),
      ),
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
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Upload'),
              style: FilledButton.styleFrom(
                backgroundColor: SchedulingOfficerColors.azureBlue,
              ),
            ),
        ],
      ),
    );
  }
}
