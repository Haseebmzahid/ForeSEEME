import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Visual mapping for a [TrendDirection]: colour + directional glyph + label.
/// The arrow direction survives greyscale, so the trend reads without colour.
class _TrendStyle {
  final Color color;
  final IconData? icon; // null => render the "—" dash (insufficient)
  final String label;

  const _TrendStyle(this.color, this.icon, this.label);

  static _TrendStyle of(TrendDirection d) => switch (d) {
    TrendDirection.rising => const _TrendStyle(
      AppColorsV2.riskHigh,
      Icons.trending_up_rounded,
      'Rising',
    ),
    TrendDirection.stable => const _TrendStyle(
      AppColorsV2.riskMedium,
      Icons.trending_flat_rounded,
      'Stable',
    ),
    TrendDirection.falling => const _TrendStyle(
      AppColorsV2.riskLow,
      Icons.trending_down_rounded,
      'Falling',
    ),
    TrendDirection.insufficient => const _TrendStyle(
      AppColorsV2.riskUncertain,
      null,
      'Insufficient data',
    ),
  };
}

/// A pill badge showing the risk trend as **arrow + label + colour** (a dash
/// "—" for insufficient history, never a misleading arrow). Pure presentation —
/// takes a [TrendDirection], so every state is testable without providers.
class TrendBadge extends StatelessWidget {
  final TrendDirection direction;

  const TrendBadge({super.key, required this.direction});

  @override
  Widget build(BuildContext context) {
    final style = _TrendStyle.of(direction);

    return Semantics(
      label: 'Risk trend: ${style.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: style.color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (style.icon != null)
              Icon(style.icon, size: 13, color: style.color)
            else
              Text(
                '—',
                style: AppTextStylesV2.caption.copyWith(
                  color: style.color,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            const SizedBox(width: 5),
            Text(
              style.label,
              style: AppTextStylesV2.caption.copyWith(
                color: style.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Provider-wired trend badge for the dashboard risk card.
///
/// Watches [riskTrendProvider]; hides itself while the trend is still loading
/// (so it animates in rather than flashing a placeholder) and falls back to the
/// insufficient treatment if the trend read fails — never a wrong arrow.
class RiskTrendBadge extends ConsumerWidget {
  const RiskTrendBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(riskTrendProvider);
    return trend.when(
      data: (direction) => TrendBadge(direction: direction),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const TrendBadge(direction: TrendDirection.insufficient),
    );
  }
}
