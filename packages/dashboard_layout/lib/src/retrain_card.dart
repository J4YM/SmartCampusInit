import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';
import 'bento_card.dart';
import 'brightness_x.dart';
import 'card_title_style.dart';
import 'responsive_x.dart';
import 'secondary_pill_button.dart';
import 'status_pill_colors.dart';

/// Mirrors the host app's `RetrainState` (see `lib/data/ml_risk_repository.dart`)
/// — this package doesn't depend on root app code, so each connected page
/// maps the real `GET /retrain/status` response down to just what
/// [RetrainCard] needs to render.
enum RetrainUiState { idle, running, completed, failed }

/// A retrain trained on fewer students than this, or tested on fewer than
/// [kMinReliableTestSamples], is flagged as a small sample. A heuristic for a
/// school-sized dataset, not a statistical rule: its only job is to stop a run
/// on a handful of records from looking like any other "Promoted".
const int kMinReliableTrainSamples = 200;
const int kMinReliableTestSamples = 50;

/// What [RetrainCard] needs from a `GET /retrain/status` response — a
/// deliberately narrow slice (not every field of the real response) since
/// this card only renders a summary, not the full result.
class RetrainStatusUiModel {
  const RetrainStatusUiModel({
    required this.state,
    this.promoted,
    this.challengerBestModelLabel,
    this.challengerRocAuc,
    this.trainingSamples,
    this.testSamples,
    this.errorMessage,
  });

  final RetrainUiState state;

  /// Set when [state] is `completed`.
  final bool? promoted;
  final String? challengerBestModelLabel;
  final double? challengerRocAuc;

  /// How many students the last run trained on / was tested on.
  final int? trainingSamples;
  final int? testSamples;

  /// True when the last run used so little data that its levels should be
  /// treated with care (a heuristic, see [kMinReliableTrainSamples]). Unknown
  /// sizes are not flagged.
  bool get isSmallSample {
    final train = trainingSamples;
    final test = testSamples;
    if (train == null || test == null) return false;
    return train < kMinReliableTrainSamples || test < kMinReliableTestSamples;
  }

  /// Set when [state] is `failed`.
  final String? errorMessage;
}

// Dark-mode values below use the app-wide neutral near-black palette
// (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
// A1A1AA/71717A text) — light mode is untouched. Same tokens as
// model_comparison_card.dart, which sits directly above this card in every
// dashboard that shows both.
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
  static Color inactiveBadgeBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
}

/// "Retrain Model Now" card — shared by every dashboard whose role may
/// trigger a retrain (Admin's ML & Thresholds page, the Guidance
/// Counselor's ML Overview tab), so the button/status/badge logic lives in
/// one place instead of being duplicated per module. Originated in the
/// Admin Dashboard's `MlThresholdsPage`, moved here the same way
/// `ModelComparisonCard` was — see that widget's own doc comment.
class RetrainCard extends StatelessWidget {
  const RetrainCard({
    super.key,
    required this.status,
    required this.retraining,
    required this.onRetrain,
  });

  final RetrainStatusUiModel? status;
  final bool retraining;

  /// `null` means retrain isn't configured at all — distinct from
  /// [retraining]/a `running` [status], both of which mean it's configured
  /// but busy right now.
  final VoidCallback? onRetrain;

  /// 1200 -> "1,200".
  static String _grouped(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  /// Retraining can change the risk level every student gets the next time
  /// they are analyzed, so ask first.
  Future<void> _confirm(BuildContext context) async {
    final run = onRetrain;
    if (run == null) return;
    final ok = await showAppPopup<bool>(
      context: context,
      builder: (_) => const _ConfirmRetrainDialog(),
    );
    if (ok == true) run();
  }

  Widget? _badge(BuildContext context) {
    final s = status;
    if (retraining || s?.state == RetrainUiState.running) {
      return _StatusBadge(
        label: 'Running…',
        background: _Colors.inactiveBadgeBg(context),
        foreground: _Colors.secondaryText(context),
      );
    }
    if (onRetrain == null) {
      return _StatusBadge(
        label: 'Not Configured',
        background: _Colors.inactiveBadgeBg(context),
        foreground: _Colors.secondaryText(context),
      );
    }
    switch (s?.state) {
      case RetrainUiState.completed:
        final promoted = s?.promoted ?? false;
        final roc = s?.challengerRocAuc;
        final rocLabel =
            roc == null ? '' : ' · ROC-AUC ${roc.toStringAsFixed(3)}';
        final (pillBg, pillFg) = promoted
            ? StatusPillColors.success(context)
            : (_Colors.inactiveBadgeBg(context), _Colors.secondaryText(context));
        return _StatusBadge(
          label: '${promoted ? 'Promoted' : 'Not promoted'}$rocLabel',
          background: pillBg,
          foreground: pillFg,
        );
      case RetrainUiState.failed:
        final (failBg, failFg) = StatusPillColors.danger(context);
        return _StatusBadge(
          label: 'Failed',
          background: failBg,
          foreground: failFg,
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
    final badge = _badge(context);
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _Colors.card(context),
        borderColor: _Colors.cardBorder(context),
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
                        'Retrain Model Now',
                        style: dashboardCardTitleStyle(context,
                            color: _Colors.primaryText(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Trigger a fresh training run against the latest data',
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 10 : 12,
                          fontWeight: FontWeight.w400,
                          color: _Colors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null) badge,
              ],
            ),
            if (status?.state == RetrainUiState.completed &&
                status?.trainingSamples != null &&
                status?.testSamples != null) ...[
              const SizedBox(height: 14),
              Text(
                'Trained on ${_grouped(status!.trainingSamples!)} students · '
                'tested on ${_grouped(status!.testSamples!)}',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  color: _Colors.secondaryText(context),
                ),
              ),
              if (status!.isSmallSample)
                Container(
                  key: const Key('retrain-small-sample-warning'),
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0A100).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    (status!.promoted ?? false)
                        ? 'Small sample. This run used very little data and it '
                            'replaced the live model, so the risk levels it '
                            'gives may differ a lot from before. Stored levels '
                            'change only when students are analyzed again; '
                            'check results before relying on them.'
                        : 'Small sample. This run used very little data. It '
                            'did not replace the live model.',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 10 : 12,
                      color: _Colors.primaryText(context),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SecondaryPillButton(
                label: isBusy ? 'Retraining…' : 'Retrain Model Now',
                icon: Icons.play_arrow_rounded,
                expand: true,
                loading: isBusy,
                onTap: onRetrain == null ? null : () => _confirm(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRetrainDialog extends StatelessWidget {
  const _ConfirmRetrainDialog();

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Retrain the model?',
      subtitle: 'This trains a new model on the latest data.',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          key: const Key('retrain-cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('retrain-confirm'),
          label: 'Retrain',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Text(
        'If the new model beats the current one it becomes the live model, and '
        'students\' risk levels can change the next time they are analyzed. '
        'With little data the result may be unreliable.',
        style: GoogleFonts.poppins(
            fontSize: 13, color: AppPopupColors.of(context).text),
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
        border: Border.all(color: _Colors.cardBorder(context)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 9 : 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return badge;
    return Tooltip(message: tooltip!, child: badge);
  }
}
