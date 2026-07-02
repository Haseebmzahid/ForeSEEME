import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';

/// Explains *why* confidence is high or low, in plain language (Sprint 5,
/// Prompt 6). Pure presentation: it visualises the backend's stored confidence
/// rationale ([strength] + [sentence]) — it computes nothing.
///
/// Accessibility: the strength is conveyed by a distinct **icon + text label**
/// (not colour alone), and the whole block carries a single Semantics label so a
/// screen reader announces the strength and the reason together.
class ConfidenceExplanation extends StatelessWidget {
  final ConfidenceStrength strength;
  final String sentence;

  const ConfidenceExplanation({
    super.key,
    required this.strength,
    required this.sentence,
  });

  @override
  Widget build(BuildContext context) {
    final style = _ConfidenceStyle.of(strength);

    return Semantics(
      label: '${style.label}. $sentence',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Strength chip — icon + label, readable in greyscale.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: style.color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, size: 13, color: style.color),
                const SizedBox(width: 5),
                Text(
                  style.label,
                  style: AppTextStylesV2.caption.copyWith(
                    color: style.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sentence,
            style: AppTextStylesV2.body.copyWith(
              color: AppColorsV2.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a [ConfidenceStrength] to a distinct icon + label + colour.
class _ConfidenceStyle {
  final IconData icon;
  final String label;
  final Color color;

  const _ConfidenceStyle(this.icon, this.label, this.color);

  static _ConfidenceStyle of(ConfidenceStrength strength) => switch (strength) {
    ConfidenceStrength.strong => const _ConfidenceStyle(
      Icons.verified_rounded,
      'Strong confidence',
      AppColorsV2.riskLow,
    ),
    ConfidenceStrength.moderate => const _ConfidenceStyle(
      Icons.thumbs_up_down_outlined,
      'Moderate confidence',
      AppColorsV2.riskMedium,
    ),
    ConfidenceStrength.weak => const _ConfidenceStyle(
      Icons.help_outline_rounded,
      'Limited confidence',
      AppColorsV2.riskUncertain,
    ),
  };
}
