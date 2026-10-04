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

// `RetrainUiState`/`RetrainStatusUiModel`/`RetrainCard` now live in
// dashboard_layout (see that package's retrain_card.dart) — shared with the
// Guidance Counselor's ML Overview tab, which can also trigger a retrain.

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _MlColors {
  static const primaryButton = Color(0xFF345892);
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color cardBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0x0DE2E8F0);
  // Shared brand accent (the same blue every other dashboard's buttons use)
  // — stays constant across themes, like every other dashboard's own accent.
  static const primaryButtonText = Color(0xFFFFFFFF);
  static Color inactiveBadgeBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color progressTrackBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF2E313A) : const Color(0xFFF1F5F9);
  static Color valueBadgeBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFE9EEF5);
  // Saturated risk/status indicator colors — read clearly on both themes,
  // so (like the brand accent) they stay constant rather than swapping.
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
    this.retrainStatus,
    this.onRetrain,
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

  /// Latest `GET /retrain/status` snapshot, or `null` if never fetched.
  final RetrainStatusUiModel? retrainStatus;

  /// Triggers `POST /retrain`. `null` when retrain isn't configured
  /// (`AppEnv.mlRetrainConfigured` false) — the button is disabled with an
  /// explanatory badge rather than hidden outright, so it's discoverable.
  /// Any error it throws is shown to the admin via a snack bar (see
  /// `_MlThresholdsPageState._handleRetrain`) — a 422 "not enough labeled
  /// data" is actionable information, not a bug to hide.
  final Future<void> Function()? onRetrain;

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

  bool _retraining = false;

  Future<void> _handleRetrain() async {
    final onRetrain = widget.onRetrain;
    if (onRetrain == null || _retraining) return;
    setState(() => _retraining = true);
    try {
      await onRetrain();
    } catch (e) {
      // MlRiskRepositoryException.toString() already returns just its
      // message (e.g. the 422 "insufficient labeled data" detail) — shown
      // plainly rather than as a generic failure, since it's actionable
      // information for the admin, not a bug.
      if (mounted) _showActionSnackBar('$e');
    } finally {
      if (mounted) setState(() => _retraining = false);
    }
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
      color: _MlColors.background(context),
      child: SafeArea(
        // The scroll view spans the full content pane (no width cap out
        // here) so its scrollbar sits at the pane's true edge; only the
        // inner content is capped at 1440px and centered.
        child: SingleChildScrollView(
          child: DashboardPageWrapper(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ML Model & Thresholds',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _MlColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tune machine learning models and alert thresholds.',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w400,
                    color: _MlColors.secondaryText(context),
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
                        RetrainCard(
                          status: widget.retrainStatus,
                          retraining: _retraining,
                          onRetrain:
                              widget.onRetrain == null ? null : _handleRetrain,
                        ),
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
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _MlColors.card(context),
        borderColor: _MlColors.cardBorder(context),
        padding: const EdgeInsets.all(20),
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
                          fontSize: context.isMobileWidth ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: _MlColors.primaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 10 : 12,
                          fontWeight: FontWeight.w400,
                          color: _MlColors.secondaryText(context),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Retrain
// ---------------------------------------------------------------------------

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
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text(
                'Save Threshold Settings',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _MlColors.primaryButton,
                foregroundColor: _MlColors.primaryButtonText,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, kDashboardControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w600,
                  color: _MlColors.primaryText(context),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _MlColors.valueBadgeBg(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLabel,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
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
            backgroundColor: _MlColors.progressTrackBackground(context),
            valueColor: AlwaysStoppedAnimation<Color>(activeColor),
          ),
        ),
      ],
    );
  }
}
