import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// The active-model card is dashboard_layout's ModelComparisonCard, which
// renders the same real per-model metrics the Guidance Counselor dashboard
// already shows (see MlThresholdsConnectedPage in the host app).
//
// `RetrainUiState`/`RetrainStatusUiModel`/`RetrainCard` live in
// dashboard_layout (see that package's retrain_card.dart) — shared with the
// Guidance Counselor's ML Overview tab, which can also trigger a retrain.

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _MlColors {
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class MlThresholdsPage extends StatefulWidget {
  const MlThresholdsPage({
    super.key,
    this.modelComparisons = const [],
    this.retrainStatus,
    this.onRetrain,
  });

  factory MlThresholdsPage.empty({Key? key}) {
    return MlThresholdsPage(key: key);
  }

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
                  'ML Model',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _MlColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Review the trained dropout-risk models and retrain on new data.',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w400,
                    color: _MlColors.secondaryText(context),
                  ),
                ),
                const SizedBox(height: 24),
                Column(
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
