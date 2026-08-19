import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data models — swap defaultRiskThresholds with Supabase/API data later.
// The active-model card (formerly MlModelDetailsModel/defaultMlModel here)
// was replaced by dashboard_layout's ModelComparisonCard, which renders the
// same real per-model metrics the Guidance Counselor dashboard already
// shows (see MlThresholdsConnectedPage in the host app).
// ---------------------------------------------------------------------------

class RiskThresholdSettingsModel {
  const RiskThresholdSettingsModel({
    this.dropoutRiskScorePercent = 0.0,
    this.unexcusedAbsenceThreshold = 0,
    this.violationIncidentCount = 0,
  });

  final double dropoutRiskScorePercent;
  final int unexcusedAbsenceThreshold;
  final int violationIncidentCount;
}

// ---------------------------------------------------------------------------
// Default (zero/empty) state — replace with repository/API calls when
// backend is ready.
// ---------------------------------------------------------------------------

const defaultRiskThresholds = RiskThresholdSettingsModel();

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _MlColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryButton = Color(0xFF27426D);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static const inactiveBadgeBg = Color(0xFFF1F5F9);
  static const progressTrackBackground = Color(0xFFF1F5F9);
  static const valueBadgeBg = Color(0xFFE9EEF5);
  static const dropoutRiskColor = Color(0xFFDC2626);
  static const unexcusedAbsenceColor = Color(0xFFEA580C);
  static const violationIncidentColor = Color(0xFFD97706);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class MlThresholdsPage extends StatefulWidget {
  const MlThresholdsPage({
    super.key,
    required this.thresholds,
    this.modelComparisons = const [],
  });

  factory MlThresholdsPage.empty({Key? key}) {
    return MlThresholdsPage(
      key: key,
      thresholds: defaultRiskThresholds,
    );
  }

  final RiskThresholdSettingsModel thresholds;

  /// Real per-model metrics from the deployed dropout-risk model's
  /// `/model-info` endpoint — same data/component as the Guidance
  /// Counselor's "Trained Model Comparison" chart. Empty when the ML
  /// service isn't configured or hasn't loaded yet.
  final List<ModelMetricModel> modelComparisons;

  @override
  State<MlThresholdsPage> createState() => _MlThresholdsPageState();
}

class _MlThresholdsPageState extends State<MlThresholdsPage> {
  late double _dropoutRiskPercent;
  late double _unexcusedAbsences;
  late double _violationCount;

  @override
  void initState() {
    super.initState();
    _dropoutRiskPercent = widget.thresholds.dropoutRiskScorePercent;
    _unexcusedAbsences = widget.thresholds.unexcusedAbsenceThreshold.toDouble();
    _violationCount = widget.thresholds.violationIncidentCount.toDouble();
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

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _MlColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ML Model & Thresholds',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _MlColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tune machine learning models and alert thresholds.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _MlColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackColumns = constraints.maxWidth < 900;

                  final modelCard = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ModelComparisonCard(models: widget.modelComparisons),
                      const SizedBox(height: 16),
                      const _RetrainUnderDevelopmentCard(),
                    ],
                  );
                  final thresholdsCard = _RiskThresholdsCard(
                    dropoutRiskPercent: _dropoutRiskPercent,
                    unexcusedAbsences: _unexcusedAbsences,
                    violationCount: _violationCount,
                    onSave: () =>
                        _showActionSnackBar('Save Threshold Settings tapped'),
                  );

                  if (stackColumns) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        modelCard,
                        const SizedBox(height: 16),
                        thresholdsCard,
                      ],
                    );
                  }

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: modelCard),
                        const SizedBox(width: 16),
                        Expanded(child: thresholdsCard),
                      ],
                    ),
                  );
                },
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.badge,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _MlColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MlColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _MlColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _MlColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) badge!,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Retrain (under development: the deployed ML service only
// exposes /predict, /predict/batch, and /model-info — no retrain endpoint
// exists to call, so this is honestly disabled rather than faked).
// ---------------------------------------------------------------------------

class _RetrainUnderDevelopmentCard extends StatelessWidget {
  const _RetrainUnderDevelopmentCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Retrain Model Now',
      subtitle: 'Trigger a fresh training run against the latest data',
      badge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _MlColors.inactiveBadgeBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _MlColors.cardBorder),
        ),
        child: Text(
          'Under Development',
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _MlColors.secondaryText,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(
            'Retrain Model Now',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Risk Thresholds
// ---------------------------------------------------------------------------

class _RiskThresholdsCard extends StatelessWidget {
  const _RiskThresholdsCard({
    required this.dropoutRiskPercent,
    required this.unexcusedAbsences,
    required this.violationCount,
    required this.onSave,
  });

  final double dropoutRiskPercent;
  final double unexcusedAbsences;
  final double violationCount;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Risk Thresholds',
      subtitle: 'Tune when students are flagged for early intervention',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ThresholdBarTile(
            label: 'Dropout Risk Score',
            valueLabel: '${dropoutRiskPercent.round()}%',
            value: dropoutRiskPercent,
            max: 100,
            activeColor: _MlColors.dropoutRiskColor,
          ),
          const SizedBox(height: 20),
          _ThresholdBarTile(
            label: 'Unexcused Absence Threshold',
            valueLabel: '${unexcusedAbsences.round()} absences',
            value: unexcusedAbsences,
            max: 20,
            activeColor: _MlColors.unexcusedAbsenceColor,
          ),
          const SizedBox(height: 20),
          _ThresholdBarTile(
            label: 'Violation Incident Count',
            valueLabel: '${violationCount.round()} incidents',
            value: violationCount,
            max: 10,
            activeColor: _MlColors.violationIncidentColor,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                'Save Threshold Settings',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _MlColors.primaryButton,
                foregroundColor: _MlColors.primaryButtonText,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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

class _ThresholdBarTile extends StatelessWidget {
  const _ThresholdBarTile({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.max,
    required this.activeColor,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double max;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final progress = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _MlColors.primaryText,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _MlColors.valueBadgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLabel,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _MlColors.primaryButton,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: _MlColors.progressTrackBackground,
            valueColor: AlwaysStoppedAnimation<Color>(activeColor),
          ),
        ),
      ],
    );
  }
}
