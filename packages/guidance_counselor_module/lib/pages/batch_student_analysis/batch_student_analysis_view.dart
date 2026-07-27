import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../single_student_analysis/single_student_analysis_view.dart'
    show AttendanceTrend, AttendanceTrendLabel;

// ---------------------------------------------------------------------------
// Data models — Supabase-ready. fromCsvRow()/toJson() map onto snake_case
// so a real batch-scoring service can be swapped in for
// [BatchStudentAnalysisView.onAnalyzeAll] without touching the UI.
// ---------------------------------------------------------------------------

/// One row of an uploaded roster, parsed from the "Batch Dataset Preview"
/// file (CSV today; see [BatchStudentAnalysisView.onPickDataset]).
class BatchStudentRecordModel {
  const BatchStudentRecordModel({
    required this.studentId,
    required this.program,
    required this.totalClasses,
    required this.totalAbsences,
    required this.maxStreak,
    required this.weeklyAbsences,
    required this.dailyAttendance30D,
    required this.absenceTrend,
    required this.recoveryScore,
  });

  final String studentId;
  final String program;
  final int totalClasses;
  final int totalAbsences;

  /// Longest run of consecutive absences on record.
  final int maxStreak;

  /// Absences in the most recent 7-day window.
  final int weeklyAbsences;

  /// e.g. "27/30" — days present out of the last 30, as supplied by the
  /// roster (not recomputed here).
  final String dailyAttendance30D;
  final AttendanceTrend absenceTrend;

  /// 0.0–1.0.
  final double recoveryScore;

  /// Derived rather than read from the file — kept in sync with
  /// [totalAbsences]/[totalClasses] instead of trusting a redundant column.
  double get absencesPercent =>
      totalClasses == 0 ? 0 : (totalAbsences / totalClasses * 100).clamp(0, 100);

  factory BatchStudentRecordModel.fromCsvRow(Map<String, String> row) {
    int readInt(String key) => int.tryParse(row[key] ?? '') ?? 0;
    double readDouble(String key) => double.tryParse(row[key] ?? '') ?? 0.0;

    return BatchStudentRecordModel(
      studentId: row['studentid'] ?? '',
      program: row['program'] ?? '',
      totalClasses: readInt('totalclasses'),
      totalAbsences: readInt('totalabsences'),
      maxStreak: readInt('maxstreak'),
      weeklyAbsences: readInt('weeklyabsences'),
      dailyAttendance30D: row['dailyattendance30d'] ?? '',
      absenceTrend: AttendanceTrendLabel.fromLabel(row['absencetrend'] ?? ''),
      recoveryScore: readDouble('recoveryscore'),
    );
  }
}

/// One row of the "Analysis Result" table, produced by scoring a
/// [BatchStudentRecordModel].
class BatchAnalysisResultModel {
  const BatchAnalysisResultModel({
    required this.studentId,
    required this.dropoutProbabilityPercent,
    required this.riskLevel,
    required this.riskReasoning,
    required this.earlyWarning30D,
  });

  final String studentId;

  /// 0–100.
  final double dropoutProbabilityPercent;

  /// "Critical", "High", "Moderate", or "Low".
  final String riskLevel;
  final String riskReasoning;

  /// "Flagged" or "None" — whether the last 30 days trip an early-warning
  /// threshold.
  final String earlyWarning30D;

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'dropout_probability_percent': dropoutProbabilityPercent,
      'risk_level': riskLevel,
      'risk_reasoning': riskReasoning,
      'early_warning_30d': earlyWarning30D,
    };
  }
}

// ---------------------------------------------------------------------------
// CSV parsing — minimal, dependency-free reader for the roster upload.
// Excel (.xlsx/.xls) files are accepted by the file picker but not parsed
// yet; that needs a binary spreadsheet reader this package doesn't pull in.
// ---------------------------------------------------------------------------

String _normalizeHeader(String header) =>
    header.trim().toLowerCase().replaceAll(RegExp(r'[\s_%]'), '');

List<String> _splitCsvLine(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ',' && !inQuotes) {
      cells.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(buffer.toString());
  return cells;
}

List<BatchStudentRecordModel> parseBatchDatasetCsv(String content) {
  final lines = content
      .split(RegExp(r'\r\n|\r|\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) return const [];

  final headers = _splitCsvLine(lines.first).map(_normalizeHeader).toList();

  return [
    for (final line in lines.skip(1))
      BatchStudentRecordModel.fromCsvRow({
        for (var i = 0; i < headers.length; i++)
          if (i < _splitCsvLine(line).length)
            headers[i]: _splitCsvLine(line)[i].trim(),
      }),
  ];
}

// ---------------------------------------------------------------------------
// Demo scoring — a placeholder used whenever the host app doesn't supply
// `onAnalyzeAll`. The real batch dropout-risk model lives in the ML service
// this eventually calls; nothing here should be treated as the source of
// truth for these numbers.
// ---------------------------------------------------------------------------

double _clampPercent(double value) => value.clamp(0, 100);

BatchAnalysisResultModel _computeDemoRowAnalysis(BatchStudentRecordModel record) {
  final absenceRate = record.absencesPercent;
  final streakPenalty = (record.maxStreak / 10).clamp(0, 1) * 20;
  final weeklyPenalty = (record.weeklyAbsences / 5).clamp(0, 1) * 15;
  final trendAdjustment = switch (record.absenceTrend) {
    AttendanceTrend.increasing => 15.0,
    AttendanceTrend.decreasing => -15.0,
    AttendanceTrend.stable => 0.0,
  };
  final recoveryAdjustment = -(record.recoveryScore * 20);

  final dropoutRisk = _clampPercent(
    absenceRate * 0.9 +
        streakPenalty +
        weeklyPenalty +
        trendAdjustment +
        recoveryAdjustment,
  );

  final riskLevel = switch (dropoutRisk) {
    >= 80 => 'Critical',
    >= 60 => 'High',
    >= 35 => 'Moderate',
    _ => 'Low',
  };

  final reasoning = [
    '${absenceRate.toStringAsFixed(0)}% absence rate',
    if (record.maxStreak >= 5) '${record.maxStreak}-day max streak',
    '${record.absenceTrend.label.toLowerCase()} trend',
  ].join(', ');

  return BatchAnalysisResultModel(
    studentId: record.studentId,
    dropoutProbabilityPercent: dropoutRisk,
    riskLevel: riskLevel,
    riskReasoning: reasoning,
    earlyWarning30D: riskLevel == 'Critical' || riskLevel == 'High' ? 'Flagged' : 'None',
  );
}

List<BatchAnalysisResultModel> _computeDemoBatchAnalysis(
  List<BatchStudentRecordModel> records,
) {
  return records.map(_computeDemoRowAnalysis).toList();
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _Colors {
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const metricLabelText = Color(0xFF475569);

  static const primaryAction = Color(0xFF345892);
  static const disabledButtonBg = Color(0xFFE2E8F0);
  static const disabledButtonText = Color(0xFF94A3B8);

  static const tableHeaderBg = Color(0xFF0F172A);

  static const criticalBg = Color(0xFFFEE2E2);
  static const criticalText = Color(0xFF991B1B);
  static const highBg = Color(0xFFFFEDD5);
  static const highText = Color(0xFF9A3412);
  static const moderateBg = Color(0xFFFEF9C3);
  static const moderateText = Color(0xFF854D0E);
  static const lowBg = Color(0xFFDCFCE7);
  static const lowText = Color(0xFF166534);
}

(Color bg, Color text) _riskLevelTint(String riskLevel) {
  return switch (riskLevel) {
    'Critical' => (_Colors.criticalBg, _Colors.criticalText),
    'High' => (_Colors.highBg, _Colors.highText),
    'Moderate' => (_Colors.moderateBg, _Colors.moderateText),
    _ => (_Colors.lowBg, _Colors.lowText),
  };
}

// ---------------------------------------------------------------------------
// State engine
// ---------------------------------------------------------------------------

/// Owns the uploaded roster, the most recent batch [results], and the
/// summary stats the right-hand metric column reads. Plain mutable fields
/// (rather than an immutable model + copyWith) so each action can call one
/// setter directly, matching [SingleStudentAnalysisController]'s pattern in
/// the sibling tab.
class BatchStudentAnalysisController extends ChangeNotifier {
  List<BatchStudentRecordModel> records = const [];
  List<BatchAnalysisResultModel> results = const [];

  bool isUploading = false;
  bool isAnalyzing = false;

  /// True once "Analyze All Student" has completed successfully at least
  /// once for the currently-loaded dataset.
  bool hasAnalyzed = false;

  String? errorMessage;

  bool get hasDataset => records.isNotEmpty;

  int get totalBatchStudents => records.length;

  int get criticalRiskCount =>
      results.where((r) => r.riskLevel == 'Critical').length;

  int get highRiskCount => results.where((r) => r.riskLevel == 'High').length;

  double get averageRiskPercentage {
    if (results.isEmpty) return 0;
    final sum = results.fold<double>(
      0,
      (total, r) => total + r.dropoutProbabilityPercent,
    );
    return sum / results.length;
  }

  void setUploading(bool value) {
    isUploading = value;
    notifyListeners();
  }

  /// Replaces the loaded roster — clears any stale results from a previous
  /// dataset so the "Analysis Result" table can't show scores for students
  /// that no longer match what's in the preview table above it.
  void setRecords(List<BatchStudentRecordModel> parsed) {
    records = parsed;
    results = const [];
    hasAnalyzed = false;
    errorMessage = null;
    notifyListeners();
  }

  void setError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  Future<void> analyzeAll({
    required Future<List<BatchAnalysisResultModel>> Function(
      List<BatchStudentRecordModel> records,
    )?
    onAnalyzeAll,
  }) async {
    if (isAnalyzing || !hasDataset) return;
    isAnalyzing = true;
    errorMessage = null;
    notifyListeners();

    try {
      results = onAnalyzeAll != null
          ? await onAnalyzeAll(records)
          : _computeDemoBatchAnalysis(records);
      hasAnalyzed = true;
    } catch (e) {
      errorMessage = 'Could not analyze this dataset: $e';
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

/// "Batch Student Analysis" tab: upload a class roster, preview it, run
/// bulk dropout-risk scoring, and review the results alongside summary
/// stats.
///
/// Relies on the ambient 1440px-capped frame the dashboard's
/// `DashboardPageWrapper` already provides around every tab — it doesn't add
/// its own max-width constraint on top of that (see [SingleStudentAnalysisView]
/// for the same convention).
class BatchStudentAnalysisView extends StatefulWidget {
  const BatchStudentAnalysisView({
    super.key,
    this.onPickDataset,
    this.onAnalyzeAll,
    this.onDownloadResults,
  });

  /// Picks and parses a roster file into records. Omit to use the built-in
  /// file_picker + CSV parser (no backend required).
  final Future<List<BatchStudentRecordModel>?> Function()? onPickDataset;

  /// Scores every uploaded record against the real ML pipeline. Omit to use
  /// the built-in demo calculator (no backend required).
  final Future<List<BatchAnalysisResultModel>> Function(
    List<BatchStudentRecordModel> records,
  )?
  onAnalyzeAll;

  /// Exports the current batch results. Omitted: just a confirmation
  /// snackbar.
  final Future<void> Function(
    List<BatchStudentRecordModel> records,
    List<BatchAnalysisResultModel> results,
  )?
  onDownloadResults;

  @override
  State<BatchStudentAnalysisView> createState() => _BatchStudentAnalysisViewState();
}

class _BatchStudentAnalysisViewState extends State<BatchStudentAnalysisView> {
  final _controller = BatchStudentAnalysisController();
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<BatchStudentRecordModel>?> _pickAndParseDataset() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked?.bytes == null) return null;

    if (!picked!.name.toLowerCase().endsWith('.csv')) {
      throw Exception(
        "Excel parsing isn't wired up yet — please upload a CSV export.",
      );
    }
    return parseBatchDatasetCsv(utf8.decode(picked.bytes!));
  }

  Future<void> _handleUploadFiles() async {
    if (_controller.isUploading) return;
    _controller.setUploading(true);
    try {
      final parsed = widget.onPickDataset != null
          ? await widget.onPickDataset!()
          : await _pickAndParseDataset();
      if (parsed == null) return; // User cancelled the picker.
      _controller.setRecords(parsed);
      _showSnackBar('${parsed.length} student records loaded.');
    } catch (e) {
      _controller.setError('Could not load this dataset: $e');
      _showSnackBar(_controller.errorMessage!);
    } finally {
      _controller.setUploading(false);
    }
  }

  Future<void> _handleAnalyzeAll() async {
    await _controller.analyzeAll(onAnalyzeAll: widget.onAnalyzeAll);
    if (_controller.errorMessage != null) _showSnackBar(_controller.errorMessage!);
  }

  Future<void> _handleDownloadResults() async {
    if (!_controller.hasAnalyzed || _downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownloadResults?.call(_controller.records, _controller.results);
      _showSnackBar('Results downloaded.');
    } catch (e) {
      _showSnackBar('Could not download results: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BatchDatasetPreviewCard(
            controller: _controller,
            onUpload: _handleUploadFiles,
            onAnalyzeAll: _handleAnalyzeAll,
          ),
          const SizedBox(height: 20),
          _AnalysisResultSection(
            controller: _controller,
            downloading: _downloading,
            onDownload: _handleDownloadResults,
          ),
        ],
      ),
    );
  }
}

/// Shared white/rounded/bordered wrapper for every card in this view.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Colors.cardBorder),
      ),
      child: child,
    );
  }
}

/// Filled action button that swaps between the primary navy style and a
/// disabled grey style depending on [enabled] — shared by "Analyze All
/// Student" and "Download Results", both inert until a dataset
/// (respectively a result set) exists.
class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : _Colors.disabledButtonText;

    return FilledButton(
      onPressed: enabled && !loading ? onTap : null,
      style: FilledButton.styleFrom(
        backgroundColor: enabled ? _Colors.primaryAction : _Colors.disabledButtonBg,
        disabledBackgroundColor: _Colors.disabledButtonBg,
        foregroundColor: foreground,
        disabledForegroundColor: _Colors.disabledButtonText,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
            )
          else
            Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TableBodyCell extends StatelessWidget {
  const _TableBodyCell(this.text, {this.textAlign = TextAlign.left, this.child});

  final String text;
  final TextAlign textAlign;

  /// When set, rendered instead of a plain [Text] — e.g. a risk-level badge.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Align(
        alignment: textAlign == TextAlign.center ? Alignment.center : Alignment.centerLeft,
        child:
            child ??
            Text(
              text,
              textAlign: textAlign,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _Colors.primaryText,
              ),
            ),
      ),
    );
  }
}

class _RiskLevelBadge extends StatelessWidget {
  const _RiskLevelBadge({required this.riskLevel});

  final String riskLevel;

  @override
  Widget build(BuildContext context) {
    final (bg, text) = _riskLevelTint(riskLevel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        riskLevel,
        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: text),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 1 — Batch Dataset Preview
// ---------------------------------------------------------------------------

class _BatchDatasetPreviewCard extends StatelessWidget {
  const _BatchDatasetPreviewCard({
    required this.controller,
    required this.onUpload,
    required this.onAnalyzeAll,
  });

  final BatchStudentAnalysisController controller;
  final VoidCallback onUpload;
  final VoidCallback onAnalyzeAll;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batch Dataset Preview',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _Colors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          _BatchDatasetTable(records: controller.records),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BatchActionButton(
                  label: 'Upload Files',
                  icon: Icons.upload_rounded,
                  enabled: true,
                  loading: controller.isUploading,
                  onTap: onUpload,
                ),
                const SizedBox(width: 12),
                _BatchActionButton(
                  label: 'Analyze All Student',
                  icon: Icons.fact_check_outlined,
                  enabled: controller.hasDataset,
                  loading: controller.isAnalyzing,
                  onTap: onAnalyzeAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchDatasetTable extends StatelessWidget {
  const _BatchDatasetTable({required this.records});

  final List<BatchStudentRecordModel> records;

  static const _placeholderRowCount = 5;
  static const _columnWidths = <int, TableColumnWidth>{
    0: FixedColumnWidth(36),
    1: FlexColumnWidth(2.2),
    2: FlexColumnWidth(1.8),
    3: FlexColumnWidth(1.6),
    4: FlexColumnWidth(1.8),
    5: FlexColumnWidth(1.6),
    6: FlexColumnWidth(1.6),
    7: FlexColumnWidth(1.8),
    8: FlexColumnWidth(2.2),
    9: FlexColumnWidth(1.8),
    10: FlexColumnWidth(1.8),
  };

  @override
  Widget build(BuildContext context) {
    final rowCount = records.isEmpty ? _placeholderRowCount : records.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(border: Border.all(color: _Colors.cardBorder)),
        child: SingleChildScrollView(
          child: Table(
            border: const TableBorder.symmetric(inside: BorderSide(color: _Colors.cardBorder)),
            columnWidths: _columnWidths,
            children: [
              const TableRow(
                decoration: BoxDecoration(color: _Colors.tableHeaderBg),
                children: [
                  _TableHeaderCell('#'),
                  _TableHeaderCell('Student ID'),
                  _TableHeaderCell('Program'),
                  _TableHeaderCell('Total Classes'),
                  _TableHeaderCell('Total Absences'),
                  _TableHeaderCell('Absences %'),
                  _TableHeaderCell('Max Streak'),
                  _TableHeaderCell('Weekly Absences'),
                  _TableHeaderCell('Daily Attendance 30D'),
                  _TableHeaderCell('Absence Trend'),
                  _TableHeaderCell('Recovery Score'),
                ],
              ),
              for (var i = 0; i < rowCount; i++)
                TableRow(
                  decoration: const BoxDecoration(color: _Colors.card),
                  children: i < records.length ? _dataCells(i, records[i]) : _placeholderCells,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dataCells(int index, BatchStudentRecordModel r) {
    return [
      _TableBodyCell('${index + 1}', textAlign: TextAlign.center),
      _TableBodyCell(r.studentId),
      _TableBodyCell(r.program),
      _TableBodyCell('${r.totalClasses}', textAlign: TextAlign.center),
      _TableBodyCell('${r.totalAbsences}', textAlign: TextAlign.center),
      _TableBodyCell('${r.absencesPercent.toStringAsFixed(1)}%', textAlign: TextAlign.center),
      _TableBodyCell('${r.maxStreak}', textAlign: TextAlign.center),
      _TableBodyCell('${r.weeklyAbsences}', textAlign: TextAlign.center),
      _TableBodyCell(r.dailyAttendance30D, textAlign: TextAlign.center),
      _TableBodyCell(r.absenceTrend.label, textAlign: TextAlign.center),
      _TableBodyCell(r.recoveryScore.toStringAsFixed(2), textAlign: TextAlign.center),
    ];
  }

  static const _placeholderCells = [
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
  ];
}

// ---------------------------------------------------------------------------
// Section 2 — Analysis Result + summary metrics
// ---------------------------------------------------------------------------

class _AnalysisResultSection extends StatelessWidget {
  const _AnalysisResultSection({
    required this.controller,
    required this.downloading,
    required this.onDownload,
  });

  final BatchStudentAnalysisController controller;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final resultCard = _AnalysisResultCard(
      controller: controller,
      downloading: downloading,
      onDownload: onDownload,
    );
    final metricsColumn = _BatchMetricsColumn(controller: controller);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        if (stackColumns) {
          return Column(
            children: [resultCard, const SizedBox(height: 20), metricsColumn],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: resultCard),
            const SizedBox(width: 20),
            SizedBox(width: 260, child: metricsColumn),
          ],
        );
      },
    );
  }
}

class _AnalysisResultCard extends StatelessWidget {
  const _AnalysisResultCard({
    required this.controller,
    required this.downloading,
    required this.onDownload,
  });

  final BatchStudentAnalysisController controller;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analysis Result',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _Colors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          _AnalysisResultTable(results: controller.results),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: _BatchActionButton(
              label: 'Download Results',
              icon: Icons.download_rounded,
              enabled: controller.hasAnalyzed,
              loading: downloading,
              onTap: onDownload,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisResultTable extends StatelessWidget {
  const _AnalysisResultTable({required this.results});

  final List<BatchAnalysisResultModel> results;

  static const _placeholderRowCount = 5;
  static const _columnWidths = <int, TableColumnWidth>{
    0: FixedColumnWidth(36),
    1: FlexColumnWidth(2),
    2: FlexColumnWidth(2),
    3: FlexColumnWidth(1.6),
    4: FlexColumnWidth(4),
    5: FlexColumnWidth(2),
  };

  @override
  Widget build(BuildContext context) {
    final rowCount = results.isEmpty ? _placeholderRowCount : results.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(border: Border.all(color: _Colors.cardBorder)),
        child: SingleChildScrollView(
          child: Table(
            border: const TableBorder.symmetric(inside: BorderSide(color: _Colors.cardBorder)),
            columnWidths: _columnWidths,
            children: [
              const TableRow(
                decoration: BoxDecoration(color: _Colors.tableHeaderBg),
                children: [
                  _TableHeaderCell('#'),
                  _TableHeaderCell('Student ID'),
                  _TableHeaderCell('Dropout Probability'),
                  _TableHeaderCell('Risk Level'),
                  _TableHeaderCell('Risk Reasoning'),
                  _TableHeaderCell('Early Warning 30D'),
                ],
              ),
              for (var i = 0; i < rowCount; i++)
                TableRow(
                  decoration: const BoxDecoration(color: _Colors.card),
                  children: i < results.length ? _dataCells(i, results[i]) : _placeholderCells,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dataCells(int index, BatchAnalysisResultModel r) {
    return [
      _TableBodyCell('${index + 1}', textAlign: TextAlign.center),
      _TableBodyCell(r.studentId),
      _TableBodyCell(
        '${r.dropoutProbabilityPercent.toStringAsFixed(1)}%',
        textAlign: TextAlign.center,
      ),
      _TableBodyCell('', textAlign: TextAlign.center, child: _RiskLevelBadge(riskLevel: r.riskLevel)),
      _TableBodyCell(r.riskReasoning),
      _TableBodyCell(r.earlyWarning30D, textAlign: TextAlign.center),
    ];
  }

  static const _placeholderCells = [
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
    _TableBodyCell(''),
  ];
}

// ---------------------------------------------------------------------------
// Right column — 4 stacked stat metric cards
// ---------------------------------------------------------------------------

class _BatchMetricsColumn extends StatelessWidget {
  const _BatchMetricsColumn({required this.controller});

  final BatchStudentAnalysisController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BatchMetricCard(label: 'Total Students', value: '${controller.totalBatchStudents}'),
        const SizedBox(height: 16),
        _BatchMetricCard(label: 'Critical Risk', value: '${controller.criticalRiskCount}'),
        const SizedBox(height: 16),
        _BatchMetricCard(label: 'High Risk', value: '${controller.highRiskCount}'),
        const SizedBox(height: 16),
        _BatchMetricCard(
          label: 'Average Risk',
          value: '${controller.averageRiskPercentage.toStringAsFixed(1)}%',
        ),
      ],
    );
  }
}

class _BatchMetricCard extends StatelessWidget {
  const _BatchMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _Colors.metricLabelText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _Colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
