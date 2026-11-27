import 'dart:convert';

import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/office_reports_repository.dart';
import '../../data/reports_repository.dart';
import '../../documents/document_letterhead.dart';
import '../../documents/document_preview_page.dart';
import '../../env.dart';

/// Wires the presentation-only [ReportsExportsPage] to real Supabase data
/// via [ReportsRepository] — "Generate Preview" runs a real query per
/// report type, "Export to PDF" hands the result to the shared
/// [DocumentPreviewPage] (preview/print/PDF/DOCX), and "Export to Excel"
/// downloads a CSV (Excel opens these natively; a true .xlsx writer isn't
/// used here since every current option has a dependency conflict with
/// docx_creator's `archive`/`xml` versions).
class ReportsExportsConnectedPage extends StatelessWidget {
  const ReportsExportsConnectedPage({
    super.key,
    this.reportTypes = adminReportTypes,
  });

  /// The report types this office can generate (Admin: all; the Discipline
  /// and Guidance offices: their own, see [disciplineReportTypes] and
  /// [guidanceReportTypes]).
  final List<String> reportTypes;

  ReportsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return ReportsRepository(Supabase.instance.client);
  }

  Future<ReportPreviewDataModel> _generatePreview(
    ReportFilterConfigModel filter,
  ) async {
    final repo = _repo;
    if (repo == null) {
      return const ReportPreviewDataModel(
        isPreviewGenerated: true,
        emptyMessage: 'Supabase is not configured.',
      );
    }
    final office = OfficeReportsRepository(Supabase.instance.client);
    final course = filter.selectedDepartment == 'All Departments'
        ? null
        : filter.selectedDepartment;
    switch (filter.reportType) {
      case 'Student Violation Summary':
        return repo.fetchViolationSummary(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'ML Dropout Risk Analysis':
        return repo.fetchMlRiskSummary(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Attendance Summary Report':
      case 'Attendance by Teacher and Subject':
        return office.fetchAttendanceByTeacherSubject(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Offense Tier Counts':
        return office.fetchOffenseTierCounts(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Suspensions':
        return office.fetchSuspensions(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Parent Acknowledgment Notices':
        return office.fetchParentAcknowledgments(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Good Moral Requests':
        return office.fetchGoodMoralRequests(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Parent Meeting Log':
        return office.fetchParentMeetingLog(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      case 'Student Behavioral Summary':
        return office.fetchBehavioralSummary(
          start: filter.startDate,
          end: filter.endDate,
          course: course,
        );
      default:
        return const ReportPreviewDataModel(isPreviewGenerated: true);
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    ReportFilterConfigModel filter,
    ReportPreviewDataModel data,
  ) async {
    final reportName = filter.reportType.isEmpty ? 'Report' : filter.reportType;
    final table = [
      data.columns,
      for (final row in data.previewRows)
        [for (final column in data.columns) '${row[column] ?? '--'}'],
    ];

    var builder = addLetterhead(DocxDocumentBuilder(), documentTitle: reportName)
        .p(
          'Department: ${filter.selectedDepartment} | Total rows: '
          '${data.totalRows}',
        );
    builder = data.previewRows.isEmpty
        ? builder.p(data.emptyMessage ?? 'No matching records found.')
        : builder.table(table);

    final document = builder.build();

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentPreviewPage(
          title: reportName,
          document: document,
          fileBaseName: reportName.replaceAll(' ', '_'),
        ),
      ),
    );
  }

  Future<void> _exportExcel(
    ReportFilterConfigModel filter,
    ReportPreviewDataModel data,
  ) async {
    final buffer = StringBuffer()
      ..writeln(data.columns.map(_csvEscape).join(','));
    for (final row in data.previewRows) {
      buffer.writeln(
        data.columns.map((column) => _csvEscape('${row[column] ?? ''}')).join(','),
      );
    }

    final reportName = filter.reportType.isEmpty ? 'Report' : filter.reportType;
    await FilePicker.saveFile(
      fileName: '${reportName.replaceAll(' ', '_')}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: utf8.encode(buffer.toString()),
    );
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    return ReportsExportsPage(
      reportTypes: reportTypes,
      filterConfig: defaultReportFilterConfig,
      previewData: defaultReportPreviewData,
      onGeneratePreview: repo == null ? null : _generatePreview,
      onExportPdf: repo == null
          ? null
          : (filter, data) => _exportPdf(context, filter, data),
      onExportExcel: repo == null ? null : _exportExcel,
    );
  }
}
