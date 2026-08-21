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

/// Package-local mirror of the host app's `RetrainState` (see
/// `lib/data/ml_risk_repository.dart`) — this package doesn't depend on
/// root app code, so the connected page maps the real API response down to
/// just what this card needs to render.
enum RetrainUiState { idle, running, completed, failed }

/// What `_RetrainCard` needs from a `GET /retrain/status` response — a
/// deliberately narrow slice (not every field of the real response) since
/// this package only renders a summary, not the full result.
class RetrainStatusUiModel {
  const RetrainStatusUiModel({
    required this.state,
    this.promoted,
    this.challengerBestModelLabel,
    this.challengerRocAuc,
    this.errorMessage,
  });

  final RetrainUiState state;

  /// Set when [state] is `completed`.
  final bool? promoted;
  final String? challengerBestModelLabel;
  final double? challengerRocAuc;

  /// Set when [state] is `failed`.
  final String? errorMessage;
}

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
                      _RetrainCard(
                        status: widget.retrainStatus,
                        retraining: _retraining,
                        onRetrain: widget.onRetrain == null
                            ? null
                            : _handleRetrain,
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
// Left column — Retrain
// ---------------------------------------------------------------------------

class _RetrainCard extends StatelessWidget {
  const _RetrainCard({
    required this.status,
    required this.retraining,
    required this.onRetrain,
  });

  final RetrainStatusUiModel? status;
  final bool retraining;

  /// `null` means retrain isn't configured at all (see
  /// `MlThresholdsPage.onRetrain`'s doc comment) — distinct from
  /// [retraining]/a `running` [status], both of which mean it's configured
  /// but busy right now.
  final VoidCallback? onRetrain;

  Widget? _badge() {
    final s = status;
    if (retraining || s?.state == RetrainUiState.running) {
      return const _StatusBadge(
        label: 'Running…',
        background: _MlColors.inactiveBadgeBg,
        foreground: _MlColors.secondaryText,
      );
    }
    if (onRetrain == null) {
      return const _StatusBadge(
        label: 'Not Configured',
        background: _MlColors.inactiveBadgeBg,
        foreground: _MlColors.secondaryText,
      );
    }
    switch (s?.state) {
      case RetrainUiState.completed:
        final promoted = s?.promoted ?? false;
        final roc = s?.challengerRocAuc;
        final rocLabel = roc == null ? '' : ' · ROC-AUC ${roc.toStringAsFixed(3)}';
        return _StatusBadge(
          label: '${promoted ? 'Promoted' : 'Not promoted'}$rocLabel',
          background: promoted ? const Color(0xFFDCFCE7) : _MlColors.inactiveBadgeBg,
          foreground: promoted ? const Color(0xFF15803D) : _MlColors.secondaryText,
        );
      case RetrainUiState.failed:
        return _StatusBadge(
          label: 'Failed',
          background: const Color(0xFFFEE2E2),
          foreground: const Color(0xFFB91C1C),
          tooltip: s?.errorMessage,
        );
      case RetrainUiState.running:
        // Already handled by the guard above — unreachable here, but the
        // switch must stay exhaustive over the nullable enum type.
        return null;
      case RetrainUiState.idle:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = retraining || status?.state == RetrainUiState.running;
    return _SectionCard(
      title: 'Retrain Model Now',
      subtitle: 'Trigger a fresh training run against the latest data',
      badge: _badge(),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (onRetrain == null || isBusy) ? null : onRetrain,
          icon: isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(
            isBusy ? 'Retraining…' : 'Retrain Model Now',
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.tooltip,
  });

  final String label;
  final Color background;
  final Color foreground;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _MlColors.cardBorder),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return badge;
    return Tooltip(message: tooltip!, child: badge);
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
