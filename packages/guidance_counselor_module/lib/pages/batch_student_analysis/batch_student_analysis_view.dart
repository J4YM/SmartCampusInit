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
    this.currentGpa,
    this.previousGpa,
    this.failingCourses,
    this.minorCount,
    this.majorACount,
    this.majorBCount,
    this.majorCCount,
    this.majorDCount,
    this.daysSinceLastViolation,
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

  /// GPA/violation fields below are null for every CSV-uploaded row (that
  /// format has no such columns — see [fromCsvRow]) and populated only by
  /// [GuidanceCounselorRepository.fetchAllStudentsForBatchAnalysis]'s live
  /// roster, which has real data to fill them from. [MlRiskRepository]
  /// sends whichever of these aren't null, so a CSV upload keeps scoring
  /// exactly as before while the live roster gets richer, more accurate
  /// predictions.
  final double? currentGpa;
  final double? previousGpa;
  final int? failingCourses;
  final int? minorCount;
  final int? majorACount;
  final int? majorBCount;
  final int? majorCCount;
  final int? majorDCount;
  final int? daysSinceLastViolation;

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
  static const primaryAction = Color(0xFF345892);
  // Dark-mode values below use the app-wide neutral near-black palette
  // (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
  // A1A1AA/71717A text) — light mode is untouched.
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0xFF22242B)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color metricLabelText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF8F8F8F);

  // Brand accent — stays constant across themes.
  static Color disabledButtonBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFE6E6E6);
  static Color disabledButtonText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF8F8F8F);

  // Brand accent (navy header row) — stays constant across themes.

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

  /// True once "Analyze All Students" has completed successfully at least
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
    this.onLoadLiveRoster,
    this.onAnalyzeAll,
    this.onDownloadResults,
    this.onViewDetails,
  });

  /// Picks and parses a roster file into records. Omit to use the built-in
  /// file_picker + CSV parser (no backend required).
  final Future<List<BatchStudentRecordModel>?> Function()? onPickDataset;

  /// Loads every currently enrolled student's real attendance/GPA/violation
  /// data as a ready-to-score dataset — an alternative to uploading an
  /// external CSV roster via [onPickDataset]/[_pickAndParseDataset], not a
  /// replacement: whichever runs most recently is what "Analyze All
  /// Student" scores. Omit to hide the "Load Live Roster" button entirely.
  final Future<List<BatchStudentRecordModel>> Function()? onLoadLiveRoster;

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

  /// Called with a result row's [BatchAnalysisResultModel.studentId] when
  /// its "View Details" action is tapped — the host switches to Single
  /// Student Analysis and runs a full lookup+analyze for that student. The
  /// column is hidden entirely when omitted (demo behavior — nowhere to
  /// navigate to).
  final ValueChanged<String>? onViewDetails;

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

  Future<void> _handleLoadLiveRoster() async {
    final onLoadLiveRoster = widget.onLoadLiveRoster;
    if (onLoadLiveRoster == null || _controller.isUploading) return;
    _controller.setUploading(true);
    try {
      final records = await onLoadLiveRoster();
      _controller.setRecords(records);
      _showSnackBar('${records.length} student records loaded.');
    } catch (e) {
      _controller.setError('Could not load the live roster: $e');
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
          onLoadLiveRoster: widget.onLoadLiveRoster == null
              ? null
              : _handleLoadLiveRoster,
          onAnalyzeAll: _handleAnalyzeAll,
        ),
        const SizedBox(height: 20),
        _AnalysisResultCard(
          controller: _controller,
          downloading: _downloading,
          onDownload: _handleDownloadResults,
          onViewDetails: widget.onViewDetails,
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
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _Colors.card(context),
        borderColor: _Colors.cardBorder(context),
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

/// Filled action button that swaps between the primary navy style and a
/// disabled grey style depending on [enabled] — shared by "Analyze All
/// Student" and "Download Results", both inert until a dataset
/// (respectively a result set) exists.
/// Compact "Upload" trigger — icon on the left, short label on the right; a
/// hover/long-press tooltip still spells out the full "Upload Files"
/// action. "Analyze All Students" keeps its labeled [_BatchActionButton];
/// only Upload was asked to change.
class _UploadFilesButton extends StatelessWidget {
  const _UploadFilesButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SecondaryPillButton(
      label: 'Upload',
      icon: Icons.upload_rounded,
      tooltip: 'Upload Files',
      loading: loading,
      onTap: onTap,
    );
  }
}

/// Loads every currently enrolled student's real data as the dataset to
/// score, instead of an uploaded CSV — see
/// [BatchStudentAnalysisView.onLoadLiveRoster]'s own doc comment. Same
/// compact icon-button shape as [_UploadFilesButton], its sibling "get me a
/// dataset" action.
class _LoadLiveRosterButton extends StatelessWidget {
  const _LoadLiveRosterButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SecondaryPillButton(
      label: 'Live Roster',
      icon: Icons.groups_rounded,
      tooltip: 'Load Live Roster',
      loading: loading,
      onTap: onTap,
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
        // Same footprint as the Upload/Live Roster pills beside it (12x8
        // padding, 12px label) — Material's 40px minimum height made this
        // one visibly taller. Standard density too: desktop platforms'
        // default compact density strips 8px off each vertical pad, which
        // left this button ~17px tall next to the 33px pills.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, kDashboardControlHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
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
                fontSize: 12,
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

/// One batch-analysis table on the app-wide table layout: header + rows (or
/// [empty] when there are none). Column flex values are the columns' old
/// pixel widths, so their proportions are unchanged; below that natural
/// width the table scrolls sideways instead of squeezing its text.
Widget _batchTable({
  required List<DashboardTableColumn> columns,
  required List<List<Widget>> rows,
  required Widget empty,
}) {
  final naturalWidth = columns.fold<double>(0, (sum, c) => sum + c.flex) +
      DashboardTableMetrics.horizontalPadding * 2 +
      DashboardTableMetrics.columnGap * (columns.length - 1);
  return DashboardTableHorizontalScroll(
    minWidth: naturalWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardTableHeader(columns: columns, topBorder: true),
        if (rows.isEmpty)
          empty
        else
          for (var i = 0; i < rows.length; i++)
            DashboardTableRow(
              columns: columns,
              showDivider: i < rows.length - 1,
              cells: rows[i],
            ),
      ],
    ),
  );
}

/// Plain text cell in the shared table body style.
Widget _cell(BuildContext context, String text, {int maxLines = 1}) => Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: dashboardTableBodyStyle(context),
    );

// ---------------------------------------------------------------------------
// Section 1 — Batch Dataset Preview
// ---------------------------------------------------------------------------

/// Shows [items] one page at a time ([BuildContext.cardPageSize] rows) via
/// [tableBuilder], with the app-wide [CardPaginationFooter] beneath once
/// there's data — a dataset/result can be a whole roster. [tableBuilder]
/// gets the page's rows plus their offset into [items] (for row numbers).
class _PagedTable<T> extends StatefulWidget {
  const _PagedTable({required this.items, required this.tableBuilder});

  final List<T> items;
  final Widget Function(List<T> pageItems, int offset) tableBuilder;

  @override
  State<_PagedTable<T>> createState() => _PagedTableState<T>();
}

class _PagedTableState<T> extends State<_PagedTable<T>> {
  int _currentPage = 1;

  @override
  void didUpdateWidget(_PagedTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new upload/analysis run is a new list — start from its top.
    if (!identical(oldWidget.items, widget.items)) _currentPage = 1;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final pageSize = context.cardPageSize;
    final totalPages = items.isEmpty ? 1 : (items.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final offset = (currentPage - 1) * pageSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.tableBuilder(
            items.skip(offset).take(pageSize).toList(), offset),
        if (items.isNotEmpty)
          DashboardTableFooter(
            child: CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: items.length,
              textColor: _Colors.metricLabelText(context),
              accentColor: _Colors.primaryAction,
              mutedBackground: context.isDarkMode
                  ? const Color(0xFF22242B)
                  : const Color(0xFFF0F5F8),
              onPrevious: () =>
                  setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
          ),
      ],
    );
  }
}

class _BatchDatasetPreviewCard extends StatelessWidget {
  const _BatchDatasetPreviewCard({
    required this.controller,
    required this.onUpload,
    required this.onLoadLiveRoster,
    required this.onAnalyzeAll,
  });

  final BatchStudentAnalysisController controller;
  final VoidCallback onUpload;
  final VoidCallback? onLoadLiveRoster;
  final VoidCallback onAnalyzeAll;

  @override
  Widget build(BuildContext context) {
    final uploadButton = _UploadFilesButton(
      loading: controller.isUploading,
      onTap: onUpload,
    );
    final liveRosterButton = onLoadLiveRoster == null
        ? null
        : _LoadLiveRosterButton(
            loading: controller.isUploading,
            onTap: onLoadLiveRoster!,
          );
    final analyzeButton = _BatchActionButton(
      label: 'Analyze All Students',
      icon: Icons.menu_book_outlined,
      enabled: controller.hasDataset,
      loading: controller.isAnalyzing,
      onTap: onAnalyzeAll,
    );

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with its actions at the top of the card; pagination stays
          // below the table.
          _CardHeader(
            title: 'Batch Dataset Preview',
            actions: [
              uploadButton,
              if (liveRosterButton != null) liveRosterButton,
              analyzeButton,
            ],
          ),
          const SizedBox(height: 16),
          _PagedTable<BatchStudentRecordModel>(
            items: controller.records,
            tableBuilder: (page, offset) =>
                _BatchDatasetTable(records: page, indexOffset: offset),
          ),
        ],
      ),
    );
  }
}

/// Card title on the left with its action buttons on the right. Wraps the
/// buttons onto their own line(s) below the title when the card is too
/// narrow for both — the labeled Analyze button is wide enough that it must
/// not be squeezed beside the title on a phone.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // Full width, not shrink-wrapped: the cards' columns are start-aligned,
    // which would otherwise park the buttons right beside the title.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }
}

class _BatchDatasetTable extends StatelessWidget {
  const _BatchDatasetTable({required this.records, this.indexOffset = 0});

  final List<BatchStudentRecordModel> records;

  /// Position of [records]' first row in the whole dataset (for "#").
  final int indexOffset;

  // Flex = each column's readable pixel width (see `_batchTable`).
  static const _columns = <DashboardTableColumn>[
    DashboardTableColumn('#', flex: 40),
    DashboardTableColumn('Student ID', flex: 110),
    DashboardTableColumn('Program', flex: 100),
    DashboardTableColumn('Total Classes', flex: 110),
    DashboardTableColumn('Total Absences', flex: 115),
    DashboardTableColumn('Absences %', flex: 95),
    DashboardTableColumn('Max Streak', flex: 95),
    DashboardTableColumn('Weekly Absences', flex: 120),
    DashboardTableColumn('Daily Attendance 30D', flex: 160),
    DashboardTableColumn('Absence Trend', flex: 110),
    DashboardTableColumn('Recovery Score', flex: 110),
  ];

  @override
  Widget build(BuildContext context) {
    // No internal *vertical* scroll box — the table renders every row at
    // its natural height and the page itself (see BatchStudentAnalysisView's
    // outer SingleChildScrollView) scrolls instead.
    return _batchTable(
      columns: _columns,
      empty: const DashboardTableEmptyState(
        icon: Icons.upload_file_outlined,
        message: 'Upload a dataset or load the live roster to preview it',
      ),
      rows: [
        for (var i = 0; i < records.length; i++)
          [
            Text('${indexOffset + i + 1}',
                style: dashboardTableMetaStyle(context)),
            Text(
              records[i].studentId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dashboardTableIdStyle(context),
            ),
            _cell(context, records[i].program),
            _cell(context, '${records[i].totalClasses}'),
            _cell(context, '${records[i].totalAbsences}'),
            _cell(context,
                '${records[i].absencesPercent.toStringAsFixed(1)}%'),
            _cell(context, '${records[i].maxStreak}'),
            _cell(context, '${records[i].weeklyAbsences}'),
            _cell(context, records[i].dailyAttendance30D),
            _cell(context, records[i].absenceTrend.label),
            _cell(context, records[i].recoveryScore.toStringAsFixed(2)),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section 2 — Analysis Result
// ---------------------------------------------------------------------------

class _AnalysisResultCard extends StatelessWidget {
  const _AnalysisResultCard({
    required this.controller,
    required this.downloading,
    required this.onDownload,
    this.onViewDetails,
  });

  final BatchStudentAnalysisController controller;
  final bool downloading;
  final VoidCallback onDownload;
  final ValueChanged<String>? onViewDetails;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Analysis Result',
            actions: [
              _BatchActionButton(
                label: 'Download Results',
                icon: Icons.download_rounded,
                enabled: controller.hasAnalyzed,
                loading: downloading,
                onTap: onDownload,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PagedTable<BatchAnalysisResultModel>(
            items: controller.results,
            tableBuilder: (page, offset) => _AnalysisResultTable(
              results: page,
              indexOffset: offset,
              onViewDetails: onViewDetails,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisResultTable extends StatelessWidget {
  const _AnalysisResultTable({
    required this.results,
    this.indexOffset = 0,
    this.onViewDetails,
  });

  final List<BatchAnalysisResultModel> results;

  /// Position of [results]' first row in the whole result set (for "#").
  final int indexOffset;

  final ValueChanged<String>? onViewDetails;

  // Flex = each column's readable pixel width (see `_batchTable`) — the
  // long-form "Risk Reasoning" column gets the most room.
  static const _columns = <DashboardTableColumn>[
    DashboardTableColumn('#', flex: 40),
    DashboardTableColumn('Student ID', flex: 110),
    DashboardTableColumn('Dropout Probability', flex: 150),
    DashboardTableColumn('Risk Level', flex: 110, compact: true),
    DashboardTableColumn('Risk Reasoning', flex: 300),
    DashboardTableColumn('Early Warning 30D', flex: 150),
    DashboardTableColumn('', flex: 60),
  ];

  @override
  Widget build(BuildContext context) {
    // No internal *vertical* scroll box — see `_BatchDatasetTable`.
    return _batchTable(
      columns: _columns,
      empty: const DashboardTableEmptyState(
        icon: Icons.analytics_outlined,
        message: 'Run Analyze All Students to see each student\'s risk',
      ),
      rows: [
        for (var i = 0; i < results.length; i++)
          [
            Text('${indexOffset + i + 1}',
                style: dashboardTableMetaStyle(context)),
            Text(
              results[i].studentId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dashboardTableIdStyle(context),
            ),
            _cell(context,
                '${results[i].dropoutProbabilityPercent.toStringAsFixed(1)}%'),
            _RiskLevelBadge(riskLevel: results[i].riskLevel),
            _cell(context, results[i].riskReasoning, maxLines: 3),
            _cell(context, results[i].earlyWarning30D),
            if (onViewDetails == null)
              const SizedBox.shrink()
            else
              Tooltip(
                message: 'View in Single Student Analysis',
                child: IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  onPressed: () => onViewDetails!(results[i].studentId),
                ),
              ),
          ],
      ],
    );
  }
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
    return BentoCard(
      backgroundColor: _Colors.card(context),
      borderColor: _Colors.cardBorder(context),
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
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
