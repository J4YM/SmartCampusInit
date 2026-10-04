import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'danger_color.dart';
import 'responsive_x.dart';
import 'secondary_pill_button.dart';

/// Mirrors the host app's `RetrainState` (see `lib/data/ml_risk_repository.dart`)
/// — this package doesn't depend on root app code, so each connected page
/// maps the real `GET /retrain/status` response down to just what
/// [RetrainCard] needs to render.
enum RetrainUiState { idle, running, completed, failed }

/// What [RetrainCard] needs from a `GET /retrain/status` response — a
/// deliberately narrow slice (not every field of the real response) since
/// this card only renders a summary, not the full result.
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
        return _StatusBadge(
          label: '${promoted ? 'Promoted' : 'Not promoted'}$rocLabel',
          background: promoted
              ? const Color(0xFFDCFCE7)
              : _Colors.inactiveBadgeBg(context),
          foreground: promoted
              ? const Color(0xFF15803D)
              : _Colors.secondaryText(context),
        );
      case RetrainUiState.failed:
        return _StatusBadge(
          label: 'Failed',
          background: const Color(0xFFFEE2E2),
          foreground: kDangerTextColor,
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
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: _Colors.primaryText(context),
                        ),
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SecondaryPillButton(
                label: isBusy ? 'Retraining…' : 'Retrain Model Now',
                icon: Icons.play_arrow_rounded,
                expand: true,
                loading: isBusy,
                onTap: onRetrain,
              ),
            ),
          ],
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
