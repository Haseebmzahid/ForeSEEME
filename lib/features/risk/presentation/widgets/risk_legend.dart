import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Colorblind-safe key mapping each risk colour to its icon + label.
///
/// Reusable across Sprint 3 surfaces (national risk map, accessibility audit).
/// Each row pairs the level colour with its distinct icon and text, so the key
/// reads correctly without relying on colour.
class RiskLegend extends StatelessWidget {
  /// Lay the levels out in a row (default) or a column.
  final Axis direction;

  const RiskLegend({super.key, this.direction = Axis.horizontal});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final a in RiskVisuals.levels) _LegendRow(appearance: a),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColorsV2.shellRaised.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('RISK LEVEL', style: AppTextStylesV2.microLabel),
          ),
          if (direction == Axis.horizontal)
            Wrap(spacing: 16, runSpacing: 8, children: rows)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  rows[i],
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final RiskAppearance appearance;

  const _LegendRow({required this.appearance});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(appearance.icon, size: 15, color: appearance.color),
        const SizedBox(width: 7),
        Text(
          appearance.label,
          style: AppTextStylesV2.body.copyWith(
            color: AppColorsV2.textPrimary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
