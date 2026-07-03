import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Small "Operator-set" pill — the consistent marker that a shown risk value was
/// manually set, not model-derived. Reused wherever an override is surfaced
/// (dashboard card, Risk Details), so the indicator reads the same everywhere.
///
/// Accessible: an icon + text label (never colour alone).
class OverrideBadge extends StatelessWidget {
  const OverrideBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Operator-set risk',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColorsV2.violet.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColorsV2.violet.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.admin_panel_settings_outlined,
              size: 13,
              color: AppColorsV2.violet,
            ),
            const SizedBox(width: 5),
            Text(
              'Operator-set',
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.violet,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full transparency banner shown on a risk surface when an operator [override]
/// is active: it states plainly that the risk was manually set, by whom, when,
/// and why, and — for honesty — what the automated model estimate was (when one
/// exists). This is the "always indicate" guarantee (Prompt 13): an override is
/// never applied silently.
class RiskOverrideNotice extends StatelessWidget {
  final RiskOverride riskOverride;

  /// The genuine model estimate the override supersedes, if any — shown as
  /// "Automated model estimate: …" so users see both.
  final RiskEstimateModel? modelEstimate;

  const RiskOverrideNotice({
    super.key,
    required this.riskOverride,
    this.modelEstimate,
  });

  @override
  Widget build(BuildContext context) {
    final a = RiskVisuals.forLevel(riskOverride.riskLevel);
    final age = riskAgeLabel(riskOverride.createdAt);
    final by = riskOverride.authorEmail.isNotEmpty
        ? riskOverride.authorEmail
        : 'an operator';

    return Semantics(
      container: true,
      label:
          'Operator-set risk for ${riskOverride.city}: ${a.headline}, '
          '${riskOverride.disease}. Set by $by $age. Reason: ${riskOverride.reason}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColorsV2.violet.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColorsV2.violet.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const OverrideBadge(),
                const Spacer(),
                Text(
                  'set $age',
                  style: AppTextStylesV2.caption.copyWith(
                    color: AppColorsV2.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The operator-set level — label + icon, never colour-only.
            Row(
              children: [
                Icon(a.icon, color: a.color, size: 22),
                const SizedBox(width: 8),
                Text(
                  a.headline,
                  style: AppTextStylesV2.cardTitle.copyWith(color: a.color),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '· ${riskOverride.disease}',
                    style: AppTextStylesV2.body.copyWith(
                      color: AppColorsV2.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'This estimate was set manually by an operator because the '
              'automated pipeline was delayed or incorrect.',
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _row(Icons.notes_rounded, 'Reason', riskOverride.reason),
            const SizedBox(height: 6),
            _row(Icons.person_outline_rounded, 'By', by),
            if (modelEstimate != null) ...[
              const SizedBox(height: 6),
              _row(
                Icons.smart_toy_outlined,
                'Automated model estimate',
                RiskVisuals.of(
                  modelEstimate!.riskLevel,
                  lowConfidence: modelEstimate!.lowConfidence,
                ).headline,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColorsV2.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.textSecondary,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
