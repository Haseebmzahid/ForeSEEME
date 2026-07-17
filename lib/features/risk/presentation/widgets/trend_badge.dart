import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Visual mapping for a [TrendDirection]: colour + directional glyph + label.
/// The arrow direction survives greyscale, so the trend reads without colour.
/// Colours come from the active theme's semantic tokens (brightness-aware).
class _TrendStyle {
  final Color color;
  final IconData? icon; // null => render the "—" dash (insufficient)
  final String label;

  const _TrendStyle(this.color, this.icon, this.label);

  static _TrendStyle of(BuildContext context, TrendDirection d) {
    final colors = context.fsmColors;
    return switch (d) {
      TrendDirection.rising => _TrendStyle(
        context.fsmPalette.error,
        Icons.trending_up_rounded,
        'Rising',
      ),
      TrendDirection.stable => _TrendStyle(
        colors.warning,
        Icons.trending_flat_rounded,
        'Stable',
      ),
      TrendDirection.falling => _TrendStyle(
        colors.success,
        Icons.trending_down_rounded,
        'Falling',
      ),
      TrendDirection.insufficient => _TrendStyle(
        context.fsmPalette.onSurfaceVariant,
        null,
        'Insufficient data',
      ),
    };
  }
}

/// A pill badge showing the risk trend as **arrow + label + colour** (a dash
/// "—" for insufficient history, never a misleading arrow). Pure presentation —
/// takes a [TrendDirection], so every state is testable without providers.
class TrendBadge extends StatelessWidget {
  final TrendDirection direction;

  const TrendBadge({super.key, required this.direction});

  @override
  Widget build(BuildContext context) {
    final style = _TrendStyle.of(context, direction);
    final caption = context.fsmText.bodySmall;

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
                style: caption?.copyWith(
                  color: style.color,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            const SizedBox(width: 5),
            Text(
              style.label,
              style: caption?.copyWith(
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
