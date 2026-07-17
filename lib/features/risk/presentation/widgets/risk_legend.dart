import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';

/// Colorblind-safe key mapping each risk colour to its icon + label.
///
/// Reusable across Sprint 3 surfaces (national risk map, accessibility audit).
/// Each row pairs the level colour with its distinct icon and text, so the key
/// reads correctly without relying on colour. Colours are resolved from the
/// active theme (brightness-aware).
class RiskLegend extends StatelessWidget {
  /// Lay the levels out in a row (default) or a column.
  final Axis direction;

  const RiskLegend({super.key, this.direction = Axis.horizontal});

  static const List<RiskLevel> _levels = [
    RiskLevel.low,
    RiskLevel.medium,
    RiskLevel.high,
  ];

  @override
  Widget build(BuildContext context) {
    final rows = [for (final level in _levels) _LegendRow(level: level)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'RISK LEVEL',
              style: context.fsmText.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: context.fsmPalette.textTertiary,
              ),
            ),
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
  final RiskLevel level;

  const _LegendRow({required this.level});

  @override
  Widget build(BuildContext context) {
    final a = RiskVisuals.resolve(context, level);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(a.icon, size: 15, color: a.color),
        const SizedBox(width: 7),
        Text(
          a.label,
          style: context.fsmText.bodySmall?.copyWith(
            color: context.fsmPalette.textPrimary,
          ),
        ),
      ],
    );
  }
}
