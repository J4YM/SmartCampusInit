import 'dart:convert';

import 'package:dashboard_layout/dashboard_layout.dart';
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
  double get absencesPercent => totalClasses == 0
      ? 0
      : (totalAbsences / totalClasses * 100).clamp(0, 100);

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

BatchAnalysisResultModel _computeDemoRowAnalysis(
    BatchStudentRecordModel record) {
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
    earlyWarning30D:
        riskLevel == 'Critical' || riskLevel == 'High' ? 'Flagged' : 'None',
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
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color metricLabelText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);

  // Brand accent — stays constant across themes.
  static const primaryAction = Color(0xFF345892);
  static Color disabledButtonBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE6E6E6);
  static Color disabledButtonText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);

  // Brand accent (navy header row) — stays constant across themes.
  static const tableHeaderBg = Color(0xFF15253F); // navy-blue

  // Soft-tint risk-level badges — richer/darker tints with brighter text in
  // dark mode so they stay legible against the dark card, keeping each
  // level's hue family (red/orange/yellow/green) recognizable.
  static Color criticalBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2);
  static Color criticalText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
  static Color highBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF431407) : const Color(0xFFFFEDD5);
  static Color highText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFDBA74) : const Color(0xFF9A3412);
  static Color moderateBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF422006) : const Color(0xFFFEF9C3);
  static Color moderateText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFDE68A) : const Color(0xFF854D0E);
  static Color lowBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF052E1B) : const Color(0xFFDCFCE7);
  static Color lowText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF86EFAC) : const Color(0xFF166534);
}

(Color bg, Color text) _riskLevelTint(BuildContext context, String riskLevel) {
  return switch (riskLevel) {
    'Critical' => (_Colors.criticalBg(context), _Colors.criticalText(context)),
    'High' => (_Colors.highBg(context), _Colors.highText(context)),
    'Moderate' => (_Colors.moderateBg(context), _Colors.moderateText(context)),
    _ => (_Colors.lowBg(context), _Colors.lowText(context)),
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
    )? onAnalyzeAll,
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
  )? onAnalyzeAll;

  /// Exports the current batch results. Omitted: just a confirmation
  /// snackbar.
  final Future<void> Function(
    List<BatchStudentRecordModel> records,
    List<BatchAnalysisResultModel> results,
  )? onDownloadResults;

  @override
  State<BatchStudentAnalysisView> createState() =>
      _BatchStudentAnalysisViewState();
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    if (_controller.errorMessage != null) {
      _showSnackBar(_controller.errorMessage!);
    }
  }

  Future<void> _handleDownloadResults() async {
    if (!_controller.hasAnalyzed || _downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownloadResults
          ?.call(_controller.records, _controller.results);
      _showSnackBar('Results downloaded.');
    } catch (e) {
      _showSnackBar('Could not download results: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The dashboard page's own outer scroll view handles the whole tab, so
    // this sizes to its own content instead of wrapping itself in another
    // SingleChildScrollView, which would be redundantly nested inside it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _BatchMetricsRow(controller: _controller),
        const SizedBox(height: 20),
        _BatchDatasetPreviewCard(
          controller: _controller,
          onUpload: _handleUploadFiles,
          onAnalyzeAll: _handleAnalyzeAll,
        ),
        const SizedBox(height: 20),
        _AnalysisResultCard(
          controller: _controller,
          downloading: _downloading,
          onDownload: _handleDownloadResults,
        ),
      ],
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
        color: _Colors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Colors.cardBorder(context)),
      ),
      child: child,
    );
  }
}

/// Filled action button that swaps between the primary navy style and a
/// disabled grey style depending on [enabled] — shared by "Analyze All
/// Student" and "Download Results", both inert until a dataset
/// (respectively a result set) exists.
/// Compact "Upload" trigger — icon on the left, short label on the right; a
/// hover/long-press tooltip still spells out the full "Upload Files"
/// action. "Analyze All Student" keeps its labeled [_BatchActionButton];
/// only Upload was asked to change.
class _UploadFilesButton extends StatelessWidget {
  const _UploadFilesButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  static Color _background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF0F5F8);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Upload Files',
      child: Material(
        color: _background(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _Colors.primaryAction,
                        ),
                      )
                    : const Icon(Icons.upload_rounded,
                        size: 16, color: _Colors.primaryAction),
                const SizedBox(width: 6),
                Text(
                  'Upload',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _Colors.primaryAction,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    final foreground =
        enabled ? Colors.white : _Colors.disabledButtonText(context);

    return FilledButton(
      onPressed: enabled && !loading ? onTap : null,
      style: FilledButton.styleFrom(
        backgroundColor:
            enabled ? _Colors.primaryAction : _Colors.disabledButtonBg(context),
        disabledBackgroundColor: _Colors.disabledButtonBg(context),
        foregroundColor: foreground,
        disabledForegroundColor: _Colors.disabledButtonText(context),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 16,
              height: 16,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: foreground),
            )
          else
            Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
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
          fontSize: context.isMobileWidth ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TableBodyCell extends StatelessWidget {
  const _TableBodyCell(this.text,
      {this.textAlign = TextAlign.left, this.child});

  final String text;
  final TextAlign textAlign;

  /// When set, rendered instead of a plain [Text] — e.g. a risk-level badge.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Align(
        alignment: textAlign == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
        child: child ??
            Text(
              text,
              textAlign: textAlign,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w500,
                color: _Colors.primaryText(context),
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
    final (bg, text) = _riskLevelTint(context, riskLevel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        riskLevel,
        style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 9 : 11, fontWeight: FontWeight.w700, color: text),
      ),
    );
  }
}

/// Sum of a column-width map's [FixedColumnWidth] values — the table's
/// natural (unsquished) width.
double _naturalTableWidth(Map<int, TableColumnWidth> fixedWidths) {
  return fixedWidths.values
      .fold<double>(0, (sum, w) => sum + (w as FixedColumnWidth).value);
}

/// Converts fixed pixel widths into proportional fractions of
/// [naturalWidth] — stretches a table's columns to fill a wider card
/// (keeping the same relative column proportions) instead of leaving a gap
/// to the right of a table rendered at its fixed natural width.
Map<int, TableColumnWidth> _stretchColumnWidths(
  Map<int, TableColumnWidth> fixedWidths,
  double naturalWidth,
) {
  return fixedWidths.map((index, width) => MapEntry(
        index,
        FractionColumnWidth((width as FixedColumnWidth).value / naturalWidth),
      ));
}

/// Shared responsive shell for the batch-analysis data tables: on a wide
/// card (available width >= the table's natural fixed-column width) the
/// columns stretch proportionally to fill the card, matching every other
/// card on this page. On a narrow card, columns keep their fixed pixel
/// widths (so text stays readable) and the table scrolls horizontally
/// instead of compressing.
Widget _responsiveDataTable({
  required Map<int, TableColumnWidth> columnWidths,
  required List<TableRow> rows,
}) {
  final naturalWidth = _naturalTableWidth(columnWidths);

  return LayoutBuilder(
    builder: (context, constraints) {
      final fitsWithoutScroll = constraints.maxWidth >= naturalWidth;

      final table = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
              border: Border.all(color: _Colors.cardBorder(context))),
          child: Table(
            border: TableBorder.symmetric(
                inside: BorderSide(color: _Colors.cardBorder(context))),
            columnWidths: fitsWithoutScroll
                ? _stretchColumnWidths(columnWidths, naturalWidth)
                : columnWidths,
            children: rows,
          ),
        ),
      );

      if (fitsWithoutScroll) return table;

      // ScrollConfiguration: Flutter's default ScrollBehavior excludes
      // mouse from dragDevices, which would otherwise leave a table wider
      // than its card unreachable for a desktop mouse user (touch/trackpad
      // drag still worked; a plain click-drag or scroll didn't).
      return ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    },
  );
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
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          _BatchDatasetTable(records: controller.records),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final uploadButton = _UploadFilesButton(
                loading: controller.isUploading,
                onTap: onUpload,
              );
              final analyzeButton = _BatchActionButton(
                label: 'Analyze All Student',
                icon: Icons.menu_book_outlined,
                enabled: controller.hasDataset,
                loading: controller.isAnalyzing,
                onTap: onAnalyzeAll,
              );

              // The labeled Analyze button is wide enough (icon + longer
              // label text) to overflow the card's right edge on a narrow
              // screen — stack it full-width instead of shrinking it below a
              // legible size. The icon-only upload button never needs that.
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    uploadButton,
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: analyzeButton),
                  ],
                );
              }

              return Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    uploadButton,
                    const SizedBox(width: 12),
                    analyzeButton,
                  ],
                ),
              );
            },
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
  // Fixed pixel widths, not FlexColumnWidth — flex columns have no minimum,
  // so at any width narrower than the table's natural content they just
  // compressed every column (and its text) down to illegible slivers.
  // Fixed widths give each column a readable floor and the table scrolls
  // horizontally (see the SingleChildScrollView in build()) instead.
  static const _columnWidths = <int, TableColumnWidth>{
    0: FixedColumnWidth(40),
    1: FixedColumnWidth(110),
    2: FixedColumnWidth(100),
    3: FixedColumnWidth(110),
    4: FixedColumnWidth(115),
    5: FixedColumnWidth(95),
    6: FixedColumnWidth(95),
    7: FixedColumnWidth(120),
    8: FixedColumnWidth(160),
    9: FixedColumnWidth(110),
    10: FixedColumnWidth(110),
  };

  @override
  Widget build(BuildContext context) {
    final rowCount = records.isEmpty ? _placeholderRowCount : records.length;

    // No internal *vertical* scroll box — the table renders every row at
    // its natural height and the page itself (see BatchStudentAnalysisView's
    // outer SingleChildScrollView) scrolls instead, matching Figma.
    // Horizontally: see `_responsiveDataTable` — fills the card on wide
    // screens, scrolls with fixed readable column widths on narrow ones.
    return _responsiveDataTable(
      columnWidths: _columnWidths,
      rows: [
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
            decoration: BoxDecoration(color: _Colors.card(context)),
            children: i < records.length
                ? _dataCells(i, records[i])
                : _placeholderCells,
          ),
      ],
    );
  }

  List<Widget> _dataCells(int index, BatchStudentRecordModel r) {
    return [
      _TableBodyCell('${index + 1}', textAlign: TextAlign.center),
      _TableBodyCell(r.studentId),
      _TableBodyCell(r.program),
      _TableBodyCell('${r.totalClasses}', textAlign: TextAlign.center),
      _TableBodyCell('${r.totalAbsences}', textAlign: TextAlign.center),
      _TableBodyCell('${r.absencesPercent.toStringAsFixed(1)}%',
          textAlign: TextAlign.center),
      _TableBodyCell('${r.maxStreak}', textAlign: TextAlign.center),
      _TableBodyCell('${r.weeklyAbsences}', textAlign: TextAlign.center),
      _TableBodyCell(r.dailyAttendance30D, textAlign: TextAlign.center),
      _TableBodyCell(r.absenceTrend.label, textAlign: TextAlign.center),
      _TableBodyCell(r.recoveryScore.toStringAsFixed(2),
          textAlign: TextAlign.center),
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
// Section 2 — Analysis Result
// ---------------------------------------------------------------------------

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
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
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
  // Fixed pixel widths, not FlexColumnWidth — see the matching comment in
  // `_BatchDatasetTable`.
  static const _columnWidths = <int, TableColumnWidth>{
    0: FixedColumnWidth(40),
    1: FixedColumnWidth(110),
    2: FixedColumnWidth(150),
    3: FixedColumnWidth(110),
    4: FixedColumnWidth(300),
    5: FixedColumnWidth(150),
  };

  @override
  Widget build(BuildContext context) {
    final rowCount = results.isEmpty ? _placeholderRowCount : results.length;

    // No internal *vertical* scroll box — see the matching comment in
    // `_BatchDatasetTable`. Horizontally: see `_responsiveDataTable` —
    // fills the card on wide screens, scrolls with fixed readable column
    // widths (especially the long-form "Risk Reasoning" one) on narrow ones.
    return _responsiveDataTable(
      columnWidths: _columnWidths,
      rows: [
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
            decoration: BoxDecoration(color: _Colors.card(context)),
            children: i < results.length
                ? _dataCells(i, results[i])
                : _placeholderCells,
          ),
      ],
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
      _TableBodyCell('',
          textAlign: TextAlign.center,
          child: _RiskLevelBadge(riskLevel: r.riskLevel)),
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
// Top row — 4 stat metric cards. Same structure as every other dashboard's
// metric card (see e.g. `_MetricCard` on the GC Overview tab, `_StatCard` in
// Professor/Discipline Officer): fromLTRB(27,16,20,16) padding, 10px radius,
// 12px/w600 muted label, 32px/w600 value, 24px icon top-right, 124px row.
// ---------------------------------------------------------------------------

class _BatchMetricsRow extends StatelessWidget {
  const _BatchMetricsRow({required this.controller});

  final BatchStudentAnalysisController controller;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _BatchMetricCard(
        label: 'Total Students',
        value: '${controller.totalBatchStudents}',
        icon: Icons.people_outline_rounded,
      ),
      _BatchMetricCard(
        label: 'Critical Risk',
        value: '${controller.criticalRiskCount}',
        icon: Icons.warning_amber_rounded,
      ),
      _BatchMetricCard(
        label: 'High Risk',
        value: '${controller.highRiskCount}',
        icon: Icons.trending_up_rounded,
      ),
      _BatchMetricCard(
        label: 'Average Risk',
        value: '${controller.averageRiskPercentage.toStringAsFixed(1)}%',
        icon: Icons.show_chart_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;

        if (isNarrow) {
          return MobileMetricGrid(cards: cards);
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BatchMetricCard extends StatelessWidget {
  const _BatchMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: _Colors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Colors.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: _Colors.metricLabelText(context),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 30 : 32,
                      fontWeight: FontWeight.w600,
                      color: _Colors.primaryText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: _Colors.metricLabelText(context)),
        ],
      ),
    );
  }
}
