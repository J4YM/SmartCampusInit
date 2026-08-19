import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data models — swap defaultReportFilterConfig/defaultReportPreviewData with
// Supabase/API-backed state later. fromJson/toJson keep the filter config
// round-trippable as query parameters for a report-generating RPC.
// ---------------------------------------------------------------------------

class ReportFilterConfigModel {
  const ReportFilterConfigModel({
    this.reportType = '',
    this.startDate,
    this.endDate,
    this.selectedDepartment = 'All Departments',
  });

  final String reportType;
  final DateTime? startDate;
  final DateTime? endDate;
  final String selectedDepartment;

  factory ReportFilterConfigModel.fromJson(Map<String, dynamic> json) {
    return ReportFilterConfigModel(
      reportType: json['reportType'] as String? ?? '',
      startDate: json['startDate'] == null
          ? null
          : DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      selectedDepartment:
          json['selectedDepartment'] as String? ?? 'All Departments',
    );
  }

  Map<String, dynamic> toJson() => {
        'reportType': reportType,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'selectedDepartment': selectedDepartment,
      };

  ReportFilterConfigModel copyWith({
    String? reportType,
    DateTime? startDate,
    DateTime? endDate,
    String? selectedDepartment,
  }) {
    return ReportFilterConfigModel(
      reportType: reportType ?? this.reportType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      selectedDepartment: selectedDepartment ?? this.selectedDepartment,
    );
  }
}

class ReportPreviewDataModel {
  const ReportPreviewDataModel({
    this.columns = const [],
    this.previewRows = const [],
    this.totalRows = 0,
    this.isPreviewGenerated = false,
    this.emptyMessage,
  });

  /// Column headers, in display order — [previewRows] entries are looked up
  /// by these same keys.
  final List<String> columns;
  final List<Map<String, dynamic>> previewRows;
  final int totalRows;
  final bool isPreviewGenerated;

  /// Overrides the generic "no rows" empty state with a report-specific
  /// explanation (e.g. "No attendance data recorded yet" for a report type
  /// with no backing data source yet) — still a real, honest result rather
  /// than placeholder rows.
  final String? emptyMessage;

  factory ReportPreviewDataModel.fromJson(Map<String, dynamic> json) {
    return ReportPreviewDataModel(
      columns: (json['columns'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      previewRows: (json['previewRows'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      totalRows: json['totalRows'] as int? ?? 0,
      isPreviewGenerated: json['isPreviewGenerated'] as bool? ?? false,
      emptyMessage: json['emptyMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'previewRows': previewRows,
        'totalRows': totalRows,
        'isPreviewGenerated': isPreviewGenerated,
        'emptyMessage': emptyMessage,
      };
}

// ---------------------------------------------------------------------------
// Default (empty) state — replace with repository/API calls when backend
// is ready.
// ---------------------------------------------------------------------------

const defaultReportFilterConfig = ReportFilterConfigModel();
const defaultReportPreviewData = ReportPreviewDataModel();

const _reportTypeOptions = [
  'Attendance Summary Report',
  'Student Violation Summary',
  'ML Dropout Risk Analysis',
];

const _departmentOptions = [
  'All Departments',
  'BSIT',
  'BSBA',
  'BSHM',
  'BSTM',
];

String _formatShortDate(DateTime? value) {
  if (value == null) return '--';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _ReportColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const fieldFill = Color(0xFFF1F5F9);
  static const primaryButton = Color(0xFF27426D);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static const chipSelectedBg = Color(0xFFDBEAFE);
  static const chipSelectedBorder = Color(0xFF2563EB);
  static const chipSelectedText = Color(0xFF1D4ED8);
  static const emptyStateIcon = Color(0xFFCBD5E1);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class ReportsExportsPage extends StatefulWidget {
  const ReportsExportsPage({
    super.key,
    required this.filterConfig,
    required this.previewData,
    this.onGeneratePreview,
    this.onExportPdf,
    this.onExportExcel,
  });

  factory ReportsExportsPage.empty({Key? key}) {
    return ReportsExportsPage(
      key: key,
      filterConfig: defaultReportFilterConfig,
      previewData: defaultReportPreviewData,
    );
  }

  final ReportFilterConfigModel filterConfig;
  final ReportPreviewDataModel previewData;

  /// Runs the report query for the current [ReportFilterConfigModel] and
  /// returns the result. When omitted, "Generate Preview" just shows an
  /// empty result (demo behavior).
  final Future<ReportPreviewDataModel> Function(
    ReportFilterConfigModel filterConfig,
  )? onGeneratePreview;

  /// Opens the generated report in the shared preview screen (preview,
  /// print, PDF/DOCX download) — lives in the host app, not this
  /// presentation-only package. Disabled until a preview has been
  /// generated.
  final Future<void> Function(
    ReportFilterConfigModel filterConfig,
    ReportPreviewDataModel previewData,
  )? onExportPdf;

  /// Downloads the generated report as a spreadsheet file. Disabled until a
  /// preview has been generated.
  final Future<void> Function(
    ReportFilterConfigModel filterConfig,
    ReportPreviewDataModel previewData,
  )? onExportExcel;

  @override
  State<ReportsExportsPage> createState() => _ReportsExportsPageState();
}

class _ReportsExportsPageState extends State<ReportsExportsPage> {
  late ReportFilterConfigModel _filterConfig;
  late ReportPreviewDataModel _previewData;
  bool _generating = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _filterConfig = widget.filterConfig;
    _previewData = widget.previewData;
  }

  void _showActionSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterConfig.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _filterConfig = _filterConfig.copyWith(startDate: picked));
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterConfig.endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _filterConfig = _filterConfig.copyWith(endDate: picked));
    }
  }

  Future<void> _generatePreview() async {
    if (_filterConfig.reportType.isEmpty || _generating) return;
    setState(() => _generating = true);
    try {
      final result = await widget.onGeneratePreview?.call(_filterConfig) ??
          const ReportPreviewDataModel(isPreviewGenerated: true);
      if (!mounted) return;
      setState(() => _previewData = result);
    } catch (e) {
      _showActionSnackBar('Could not generate report: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await widget.onExportPdf?.call(_filterConfig, _previewData);
    } catch (e) {
      _showActionSnackBar('Could not export report: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await widget.onExportExcel?.call(_filterConfig, _previewData);
      _showActionSnackBar('Report downloaded.');
    } catch (e) {
      _showActionSnackBar('Could not export report: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _ReportColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports & Exports',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _ReportColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Generate reports and export dashboard data.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _ReportColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stackColumns = constraints.maxWidth < 900;

                    final generatorCard = _ReportGeneratorCard(
                      filterConfig: _filterConfig,
                      onReportTypeChanged: (value) => setState(() =>
                          _filterConfig =
                              _filterConfig.copyWith(reportType: value ?? '')),
                      onPickStartDate: _pickStartDate,
                      onPickEndDate: _pickEndDate,
                      onDepartmentSelected: (dept) => setState(() =>
                          _filterConfig =
                              _filterConfig.copyWith(selectedDepartment: dept)),
                      onGeneratePreview: _generatePreview,
                      isGenerating: _generating,
                    );

                    final contextCard =
                        _ReportContextCard(filterConfig: _filterConfig, previewData: _previewData);

                    final dataPreviewCard =
                        _DataPreviewCard(previewData: _previewData);

                    final exportCard = _ExportReportCard(
                      isEnabled: _previewData.isPreviewGenerated && !_exporting,
                      onExportPdf: _exportPdf,
                      onExportExcel: _exportExcel,
                    );

                    if (stackColumns) {
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            generatorCard,
                            const SizedBox(height: 16),
                            contextCard,
                            const SizedBox(height: 16),
                            SizedBox(height: 320, child: dataPreviewCard),
                            const SizedBox(height: 16),
                            exportCard,
                          ],
                        ),
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                generatorCard,
                                const SizedBox(height: 16),
                                contextCard,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: dataPreviewCard),
                              const SizedBox(height: 16),
                              exportCard,
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card chrome
// ---------------------------------------------------------------------------

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _ReportColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ReportColors.cardBorder),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Report Generator
// ---------------------------------------------------------------------------

class _ReportGeneratorCard extends StatelessWidget {
  const _ReportGeneratorCard({
    required this.filterConfig,
    required this.onReportTypeChanged,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onDepartmentSelected,
    required this.onGeneratePreview,
    this.isGenerating = false,
  });

  final ReportFilterConfigModel filterConfig;
  final ValueChanged<String?> onReportTypeChanged;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final ValueChanged<String> onDepartmentSelected;
  final VoidCallback onGeneratePreview;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: _ReportColors.primaryText,
              ),
              const SizedBox(width: 8),
              Text(
                'Report Generator',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ReportColors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Report Type',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ReportColors.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          _ReportTypeDropdown(
            value: filterConfig.reportType.isEmpty ? null : filterConfig.reportType,
            onChanged: onReportTypeChanged,
          ),
          const SizedBox(height: 16),
          Text(
            'Date Range',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ReportColors.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  value: filterConfig.startDate,
                  onTap: onPickStartDate,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: _ReportColors.secondaryText,
                ),
              ),
              Expanded(
                child: _DateField(
                  value: filterConfig.endDate,
                  onTap: onPickEndDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Department / Program',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ReportColors.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          _DepartmentChipGrid(
            selected: filterConfig.selectedDepartment,
            onSelected: onDepartmentSelected,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  filterConfig.reportType.isEmpty || isGenerating
                      ? null
                      : onGeneratePreview,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.science_outlined, size: 18),
              label: Text(
                isGenerating ? 'Generating…' : 'Generate Preview',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _ReportColors.primaryButton,
                foregroundColor: _ReportColors.primaryButtonText,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTypeDropdown extends StatelessWidget {
  const _ReportTypeDropdown({
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: value,
      onChanged: onChanged,
      isExpanded: true,
      style: GoogleFonts.poppins(
        fontSize: 13,
        color: _ReportColors.primaryText,
      ),
      hint: Text(
        'Select Report Type...',
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: _ReportColors.secondaryText,
        ),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: _ReportColors.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _ReportColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _ReportColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _ReportColors.primaryButton),
        ),
      ),
      items: [
        for (final option in _reportTypeOptions)
          DropdownMenuItem<String?>(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.onTap,
  });

  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _ReportColors.fieldFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ReportColors.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? 'mm/dd/yyyy' : _formatShortDate(value),
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: value == null
                      ? _ReportColors.secondaryText
                      : _ReportColors.primaryText,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: _ReportColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentChipGrid extends StatelessWidget {
  const _DepartmentChipGrid({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _departmentOptions.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DepartmentChip(
                  label: _departmentOptions[i],
                  isSelected: selected == _departmentOptions[i],
                  onTap: () => onSelected(_departmentOptions[i]),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < _departmentOptions.length
                    ? _DepartmentChip(
                        label: _departmentOptions[i + 1],
                        isSelected: selected == _departmentOptions[i + 1],
                        onTap: () => onSelected(_departmentOptions[i + 1]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DepartmentChip extends StatelessWidget {
  const _DepartmentChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _ReportColors.chipSelectedBg : _ReportColors.fieldFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? _ReportColors.chipSelectedBorder
                : _ReportColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? _ReportColors.chipSelectedText
                : _ReportColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Report Context summary
// ---------------------------------------------------------------------------

class _ReportContextCard extends StatelessWidget {
  const _ReportContextCard({
    required this.filterConfig,
    required this.previewData,
  });

  final ReportFilterConfigModel filterConfig;
  final ReportPreviewDataModel previewData;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'REPORT CONTEXT',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: _ReportColors.secondaryText,
            ),
          ),
          const SizedBox(height: 16),
          _ContextRow(
            label: 'Selected Report',
            value: filterConfig.reportType.isEmpty ? '--' : filterConfig.reportType,
          ),
          const SizedBox(height: 10),
          _ContextDateRangeRow(
            label: 'Date Range',
            startDate: filterConfig.startDate,
            endDate: filterConfig.endDate,
          ),
          const SizedBox(height: 10),
          _ContextRow(
            label: 'Department',
            value: filterConfig.selectedDepartment,
          ),
          const SizedBox(height: 10),
          _ContextRow(
            label: 'Preview Rows',
            value: '${previewData.previewRows.length}',
          ),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _ReportColors.secondaryText,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ReportColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContextDateRangeRow extends StatelessWidget {
  const _ContextDateRangeRow({
    required this.label,
    required this.startDate,
    required this.endDate,
  });

  final String label;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  Widget build(BuildContext context) {
    final valueStyle = GoogleFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _ReportColors.primaryText,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _ReportColors.secondaryText,
            ),
          ),
        ),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _formatShortDate(startDate),
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 12,
                  color: _ReportColors.secondaryText,
                ),
              ),
              Flexible(
                child: Text(
                  _formatShortDate(endDate),
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Data Preview
// ---------------------------------------------------------------------------

class _DataPreviewCard extends StatelessWidget {
  const _DataPreviewCard({required this.previewData});

  final ReportPreviewDataModel previewData;

  @override
  Widget build(BuildContext context) {
    final isEmpty = !previewData.isPreviewGenerated || previewData.previewRows.isEmpty;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _ReportColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ReportColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Data Preview',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _ReportColors.primaryText,
                    ),
                  ),
                ),
                Text(
                  '${previewData.totalRows} rows · First ${previewData.previewRows.length} shown',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _ReportColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _ReportColors.cardBorder),
          Expanded(
            child: isEmpty
                ? _EmptyPreviewState(
                    message: previewData.isPreviewGenerated
                        ? (previewData.emptyMessage ?? 'No matching records found.')
                        : null,
                  )
                : _ReportDataTable(previewData: previewData),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreviewState extends StatelessWidget {
  const _EmptyPreviewState({this.message});

  /// Overrides the default "not generated yet" prompt — used once a
  /// preview has actually been generated but genuinely has no rows.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              message == null
                  ? Icons.bar_chart_rounded
                  : Icons.inbox_outlined,
              size: 40,
              color: _ReportColors.emptyStateIcon,
            ),
            const SizedBox(height: 12),
            Text(
              message ?? 'Configure your report and click Generate Preview',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _ReportColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable (both axes) table of [ReportPreviewDataModel.previewRows] —
/// column set varies per report type, so this reads [columns] generically
/// rather than hard-coding any report's specific fields.
class _ReportDataTable extends StatelessWidget {
  const _ReportDataTable({required this.previewData});

  final ReportPreviewDataModel previewData;

  @override
  Widget build(BuildContext context) {
    final headerStyle = GoogleFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: _ReportColors.primaryText,
    );
    final cellStyle = GoogleFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _ReportColors.primaryText,
    );

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_ReportColors.fieldFill),
            columns: [
              for (final column in previewData.columns)
                DataColumn(label: Text(column, style: headerStyle)),
            ],
            rows: [
              for (final row in previewData.previewRows)
                DataRow(
                  cells: [
                    for (final column in previewData.columns)
                      DataCell(
                        Text('${row[column] ?? '--'}', style: cellStyle),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Export Report action bar
// ---------------------------------------------------------------------------

class _ExportReportCard extends StatelessWidget {
  const _ExportReportCard({
    required this.isEnabled,
    required this.onExportPdf,
    required this.onExportExcel,
  });

  final bool isEnabled;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 520;

          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Export Report',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ReportColors.primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Generate a preview first before exporting',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: _ReportColors.secondaryText,
                ),
              ),
            ],
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ExportButton(
                icon: Icons.download_rounded,
                label: 'Export to PDF',
                onPressed: isEnabled ? onExportPdf : null,
              ),
              const SizedBox(width: 12),
              _ExportButton(
                icon: Icons.download_rounded,
                label: 'Export to Excel / CSV',
                onPressed: isEnabled ? onExportExcel : null,
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 16),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _ReportColors.primaryText,
        disabledForegroundColor: _ReportColors.secondaryText.withOpacity(0.5),
        side: const BorderSide(color: _ReportColors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
