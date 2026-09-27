import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart' show SectionScheduleRowModel;
import 'package:flutter/material.dart';
import 'package:scheduling_officer_module/scheduling_officer_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/registrar_repository.dart';
import '../data/schedule_import_repository.dart';
import '../data/schedule_import_runner.dart';
import '../data/section_schedule_repository.dart';
import '../documents/section_schedule_pdf.dart';
import '../env.dart';

/// Wires [SchedulingOfficerDashboardPage] to Supabase: the readiness banner
/// (has the Registrar uploaded the Classes+Professor list for the selected
/// school year/term?) and the two file uploads, both routed through the
/// same [ScheduleImportRunner] the Registrar's own Class Schedule import
/// already uses — it already dispatches on detected file format
/// (Faculty Loading / Room Schedule / Classes+Professor list) and commits
/// class_sections/class_section_meetings generically, so no new import
/// logic is needed here, only the dashboard shell around it.
class SchedulingOfficerConnectedPage extends StatefulWidget {
  const SchedulingOfficerConnectedPage({
    super.key,
    this.officerName,
    this.onSignOut,
  });

  final String? officerName;
  final VoidCallback? onSignOut;

  @override
  State<SchedulingOfficerConnectedPage> createState() =>
      _SchedulingOfficerConnectedPageState();
}

class _SchedulingOfficerConnectedPageState
    extends State<SchedulingOfficerConnectedPage> {
  RegistrarRepository? get _registrarRepo => AppEnv.supabaseConfigured
      ? RegistrarRepository(Supabase.instance.client)
      : null;

  ScheduleImportRunner? get _importRunner {
    if (!AppEnv.supabaseConfigured) return null;
    final client = Supabase.instance.client;
    return ScheduleImportRunner(
      scheduleImportRepository: ScheduleImportRepository(client),
      registrarRepository: RegistrarRepository(client),
    );
  }

  SectionScheduleRepository? get _sectionScheduleRepo => AppEnv.supabaseConfigured
      ? SectionScheduleRepository(Supabase.instance.client)
      : null;

  late String _schoolYear;
  String _term = '1st Semester';
  int? _existingOfferingsCount;
  List<({String id, String name})> _sectionOptions = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    _schoolYear = '$startYear-${startYear + 1}';
    _loadReadiness();
    _loadSectionOptions();
  }

  Future<void> _loadSectionOptions() async {
    final repo = _sectionScheduleRepo;
    if (repo == null) return;
    try {
      final options = await repo.fetchSectionOptions();
      if (mounted) {
        setState(() {
          _sectionOptions = [for (final o in options) (id: o.id, name: o.name)];
        });
      }
    } catch (e) {
      debugPrint('Could not load section options: $e');
    }
  }

  Future<List<SectionScheduleRowModel>> _handleSectionScheduleSelected(
    String sectionId,
  ) async {
    final repo = _sectionScheduleRepo;
    if (repo == null) return const [];
    final entries = await repo.fetchSectionSchedule(sectionId: sectionId);
    return entries
        .map((e) => SectionScheduleRowModel(
              classSectionId: e.classSectionId,
              subjectCode: e.subjectCode,
              subjectTitle: e.subjectTitle,
              professorName: e.professorName,
              component: e.component,
              day: e.day,
              startTime: e.startTime,
              endTime: e.endTime,
              room: e.room,
              units: e.units,
              schoolYear: e.schoolYear,
              term: e.term,
            ))
        .toList();
  }

  List<SectionSchedulePdfRow> _toPdfRows(List<SectionScheduleRowModel> rows) =>
      rows
          .map((r) => SectionSchedulePdfRow(
                classSectionId: r.classSectionId,
                subjectCode: r.subjectCode,
                subjectTitle: r.subjectTitle,
                professorName: r.professorName,
                component: r.component,
                day: r.day,
                startTime: r.startTime,
                endTime: r.endTime,
                room: r.room,
                units: r.units,
                schoolYear: r.schoolYear,
                term: r.term,
              ))
          .toList();

  Future<void> _handleExportSectionSchedulePdf(
    String sectionName,
    List<SectionScheduleRowModel> rows,
  ) async {
    await exportSectionSchedulePdf(
      sectionName: sectionName,
      rows: _toPdfRows(rows),
    );
  }

  Future<void> _handleExportSectionScheduleExcel(
    String sectionName,
    List<SectionScheduleRowModel> rows,
  ) async {
    await exportSectionScheduleCsv(
      sectionName: sectionName,
      rows: _toPdfRows(rows),
    );
  }

  /// Not re-fetched on school year/term changes: the count is a global
  /// subjects-table check (see RegistrarRepository.countExistingOfferings),
  /// not scoped to a particular school year/term, so it can't change based
  /// on that selection.
  Future<void> _loadReadiness() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final count = await repo.countExistingOfferings();
      if (mounted) setState(() => _existingOfferingsCount = count);
    } catch (e) {
      debugPrint('Could not load Scheduling Officer readiness count: $e');
    }
  }

  void _handleSchoolYearOrTermChanged(String schoolYear, String term) {
    setState(() {
      _schoolYear = schoolYear;
      _term = term;
    });
  }

  Future<SchedulingOfficerUploadResult> _handleUpload({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  }) async {
    final runner = _importRunner;
    if (runner == null) {
      throw Exception('Supabase is not configured.');
    }
    final summary = await runner.run(
      xlsxBytes: bytes,
      schoolYear: schoolYear,
      term: term,
    );
    await _loadReadiness();
    await _loadSectionOptions();
    return SchedulingOfficerUploadResult(
      offeringsCommitted: summary.offeringsCommitted,
      meetingsCommitted: summary.meetingsCommitted,
      errors: summary.errors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final runner = _importRunner;
    return SchedulingOfficerDashboardPage(
      officerName: widget.officerName ?? 'Scheduling Officer',
      onSignOut: widget.onSignOut,
      existingOfferingsCount: _existingOfferingsCount,
      initialSchoolYear: _schoolYear,
      initialTerm: _term,
      onSchoolYearOrTermChanged: _handleSchoolYearOrTermChanged,
      onUploadFacultyLoading: runner == null ? null : _handleUpload,
      onUploadRoomSchedule: runner == null ? null : _handleUpload,
      sectionScheduleOptions: _sectionOptions,
      onSectionScheduleSelected:
          _sectionScheduleRepo == null ? null : _handleSectionScheduleSelected,
      onExportSectionSchedulePdf: _handleExportSectionSchedulePdf,
      onExportSectionScheduleExcel: _handleExportSectionScheduleExcel,
    );
  }
}
