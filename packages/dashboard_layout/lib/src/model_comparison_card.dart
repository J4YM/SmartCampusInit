import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'responsive_x.dart';

/// One trained model's evaluation scores (all 0.0–1.0) behind a group of
/// bars in [ModelComparisonCard]. Shared across every module that shows the
/// deployed dropout-risk model's real metrics (`GET /model-info`) — moved
/// here (out of `guidance_counselor_module`, which originated it) so the
/// Admin Dashboard's ML & Thresholds page can render the exact same
/// interface against the same data instead of its own disconnected mock.
class ModelMetricModel {
  const ModelMetricModel({
    required this.modelName,
    required this.rocAuc,
    required this.prAuc,
    required this.recall,
    required this.f1,
  });

  final String modelName;
  final double rocAuc;
  final double prAuc;
  final double recall;
  final double f1;

  factory ModelMetricModel.fromJson(Map<String, dynamic> json) {
    return ModelMetricModel(
      modelName: json['model_name'] as String,
      rocAuc: (json['roc_auc'] as num?)?.toDouble() ?? 0.0,
      prAuc: (json['pr_auc'] as num?)?.toDouble() ?? 0.0,
      recall: (json['recall'] as num?)?.toDouble() ?? 0.0,
      f1: (json['f1'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model_name': modelName,
      'roc_auc': rocAuc,
      'pr_auc': prAuc,
      'recall': recall,
      'f1': f1,
    };
  }
}

// Dark-mode values below use the app-wide neutral near-black palette
// (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
// A1A1AA/71717A text) — light mode is untouched.
abstract final class _Colors {
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0xFF22242B)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);

  // Shared 4-stop violet ramp — roc_auc darkest through f1 lightest. Same
  // hue family as the Admin Dashboard's "Discipline Alerts — Last 7 Days"
  // bars (8B5CF6 / C4B5FD). Brand/chart accent colors, stay constant across
  // themes.
  static const chartTone1 = Color(0xFF5B21B6);
  static const chartTone2 = Color(0xFF8B5CF6);
  static const chartTone3 = Color(0xFFA78BFA);
  static const chartTone4 = Color(0xFFC4B5FD);
}

/// "Trained Model Comparison" grouped-bar-chart card — every model in
/// [models] compared across roc_auc/pr_auc/recall/f1. Self-contained (own
/// card chrome, legend, and chart), so it drops into any dashboard's layout
/// as a single widget. Styled after the Admin Dashboard's "Discipline
/// Alerts" bar chart: small uppercase title, rounded bars with their value
/// on top, model names underneath, no axis or gridlines.
class ModelComparisonCard extends StatelessWidget {
  const ModelComparisonCard({super.key, required this.models});

  final List<ModelMetricModel> models;

  static const _seriesLegend = [
    ('roc_auc', _Colors.chartTone1),
    ('pr_auc', _Colors.chartTone2),
    ('recall', _Colors.chartTone3),
    ('f1', _Colors.chartTone4),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _Colors.card(context),
        borderColor: _Colors.cardBorder(context),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TRAINED MODEL COMPARISON',
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 9 : 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: _Colors.secondaryText(context),
              ),
            ),
            const SizedBox(height: 16),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No model metrics available.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: _Colors.secondaryText(context),
                    ),
                  ),
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _GroupedBarChart(models: models)),
                  const SizedBox(width: 24),
                  const _ChartLegend(entries: _seriesLegend),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Colored dot + label, stacked vertically.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.entries});

  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: entry.$2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                entry.$1,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w500,
                  color: _Colors.primaryText(context),
                ),
              ),
            ],
          ),
          if (entry != entries.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Splits models into rows of at most [_modelsPerRow] so each row's bar
/// groups have room to breathe — a single row of all models ran out of
/// horizontal space at mobile widths (each group needs ~60px for its 4
/// bars), overflowing off the card's right edge.
class _GroupedBarChart extends StatelessWidget {
  const _GroupedBarChart({required this.models});

  final List<ModelMetricModel> models;

  static const _modelsPerRow = 2;

  @override
  Widget build(BuildContext context) {
    final rows = <List<ModelMetricModel>>[
      for (var i = 0; i < models.length; i += _modelsPerRow)
        models.sublist(i, math.min(i + _modelsPerRow, models.length)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _GroupedBarChartRow(models: rows[i]),
          if (i != rows.length - 1) const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _GroupedBarChartRow extends StatelessWidget {
  const _GroupedBarChartRow({required this.models});

  final List<ModelMetricModel> models;

  static const barAreaHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final model in models) Expanded(child: _BarGroup(model: model)),
      ],
    );
  }
}

class _BarGroup extends StatelessWidget {
  const _BarGroup({required this.model});

  final ModelMetricModel model;

  static const _gap = 6.0;
  static const _maxBarWidth = 28.0;
  static const _labelHeight = 16.0;
  static const _seriesNames = ['roc_auc', 'pr_auc', 'recall', 'f1'];

  @override
  Widget build(BuildContext context) {
    final values = [model.rocAuc, model.prAuc, model.recall, model.f1];
    const colors = [
      _Colors.chartTone1,
      _Colors.chartTone2,
      _Colors.chartTone3,
      _Colors.chartTone4,
    ];

    // Bar width is derived from the space this group is actually given
    // (its Expanded share of the row) rather than a fixed value, so the
    // group can never demand more width than it has — a fixed width
    // overflowed on narrow phones once enough model groups were packed
    // into one row.
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = ((constraints.maxWidth - _gap * (values.length - 1)) /
                values.length)
            .clamp(1.0, _maxBarWidth);
        const maxBarHeight = _GroupedBarChartRow.barAreaHeight - _labelHeight;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _GroupedBarChartRow.barAreaHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++) ...[
                    _Bar(
                      tooltip:
                          '${model.modelName} · ${_seriesNames[i]}: ${values[i].toStringAsFixed(2)}',
                      value: values[i],
                      color: colors[i],
                      maxHeight: maxBarHeight,
                      width: barWidth,
                      labelHeight: _labelHeight,
                    ),
                    if (i != values.length - 1) const SizedBox(width: _gap),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              model.modelName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 9 : 11,
                fontWeight: FontWeight.w500,
                color: _Colors.secondaryText(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.tooltip,
    required this.value,
    required this.color,
    required this.maxHeight,
    required this.width,
    required this.labelHeight,
  });

  /// Hover hint naming exactly which model/metric this bar is.
  final String tooltip;
  final double value;
  final Color color;
  final double maxHeight;
  final double width;
  final double labelHeight;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelHeight,
              // Scales the score down to fit rather than overflowing when the
              // bar is narrower than its own label (small phones).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value.toStringAsFixed(2),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _Colors.primaryText(context),
                  ),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: maxHeight * value.clamp(0.0, 1.0),
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
