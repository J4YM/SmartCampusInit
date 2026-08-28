import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

abstract final class _Colors {
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color gridLine(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  // Shared 4-stop blue ramp — roc_auc darkest through f1 lightest. Brand/
  // chart accent colors, stay constant across themes.
  static const chartTone1 = Color(0xFF0F172A);
  static const chartTone2 = Color(0xFF2563EB);
  static const chartTone3 = Color(0xFF06B6D4);
  static const chartTone4 = Color(0xFFA5F3FC);
}

/// "Trained Model Comparison" grouped-bar-chart card — every model in
/// [models] compared across roc_auc/pr_auc/recall/f1. Self-contained (own
/// card chrome, legend, and chart), so it drops into any dashboard's layout
/// as a single widget.
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Colors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Colors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Trained Model Comparison',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w700,
              color: _Colors.primaryText(context),
            ),
          ),
          const SizedBox(height: 24),
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

  static const chartHeight = 220.0;
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

  static const _ticks = [1.0, 0.8, 0.6, 0.4, 0.2, 0.0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _GroupedBarChart.chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final tick in _ticks)
                      Text(
                        tick == tick.roundToDouble()
                            ? '${tick.toInt()}'
                            : '$tick',
                        style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 8 : 10,
                            color: _Colors.secondaryText(context)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < _ticks.length; i++)
                          Container(
                              height: 1, color: _Colors.gridLine(context)),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final model in models)
                          Expanded(
                            child: _BarGroup(
                                model: model,
                                maxHeight: _GroupedBarChart.chartHeight),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(width: 36),
            Expanded(
              child: Row(
                children: [
                  for (final model in models)
                    Expanded(
                      child: Text(
                        model.modelName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 10 : 12,
                          fontWeight: FontWeight.w500,
                          color: _Colors.primaryText(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BarGroup extends StatelessWidget {
  const _BarGroup({required this.model, required this.maxHeight});

  final ModelMetricModel model;
  final double maxHeight;

  static const _gap = 4.0;
  static const _maxBarWidth = 12.0;

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
    // (its Expanded share of the row) rather than a fixed 12px, so the
    // group can never demand more width than it has — a fixed width
    // overflowed on narrow phones once enough model groups were packed
    // into one row.
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = ((constraints.maxWidth - _gap * (values.length - 1)) /
                values.length)
            .clamp(1.0, _maxBarWidth);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              _Bar(
                value: values[i],
                color: colors[i],
                maxHeight: maxHeight,
                width: barWidth,
              ),
              if (i != values.length - 1) const SizedBox(width: _gap),
            ],
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.color,
    required this.maxHeight,
    required this.width,
  });

  final double value;
  final Color color;
  final double maxHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: maxHeight * value.clamp(0, 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }
}
