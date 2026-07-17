import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_prioritizer.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';

/// Environmental Insights card (Sprint 5, Prompt 10).
///
/// Surfaces the genuine environmental drivers behind the current estimate (from
/// the stored model attributions) and the most-relevant cited guidance first
/// (deterministic prioritization). Pure presentation: it reads
/// [environmentalInsightsProvider] and only formats it — it recomputes nothing
/// and generates no medical text (advisories are cited lookups).
///
/// Degrades quietly: while loading it shows a small skeleton; on error or when
/// there is nothing to show (no estimate / no attributions) it renders nothing,
/// so the surrounding screen stays clean.
class EnvironmentalInsightsCard extends ConsumerWidget {
  const EnvironmentalInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(environmentalInsightsProvider);
    return async.when(
      loading: () => const AppSkeleton(child: SkeletonBox(height: 150, radius: 20)),
      error: (_, _) => const SizedBox.shrink(),
      data: (view) =>
          view.hasContent ? _Card(view: view) : const SizedBox.shrink(),
    );
  }
}

class _Card extends StatelessWidget {
  final EnvironmentalInsightsView view;
  const _Card({required this.view});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final estimate = view.estimate!;
    final level = estimate.riskLevel.toJson();
    final maxMagnitude = view.drivers.isEmpty
        ? 1.0
        : view.drivers.map((d) => d.magnitude).reduce((a, b) => a > b ? a : b);
    // Show the top two prioritized advisories (most relevant first).
    final guidance = view.guidance.take(2).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco_outlined, size: 18, color: palette.primary),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Expanded(
                child: Text(
                  'Environmental drivers',
                  style: text.titleMedium?.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          if (view.drivers.isNotEmpty) ...[
            const SizedBox(height: ForeSeeMeSpacing.sm),
            Text(
              'The main factors shaping this week’s $level ${estimate.disease} '
              'estimate:',
              style: text.bodyLarge?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: ForeSeeMeSpacing.md),
            for (final driver in view.drivers) ...[
              _DriverRow(driver: driver, maxMagnitude: maxMagnitude),
              const SizedBox(height: ForeSeeMeSpacing.md),
            ],
          ],
          if (guidance.isNotEmpty) ...[
            const SizedBox(height: 2),
            Divider(height: 1, color: palette.outlineVariant),
            const SizedBox(height: ForeSeeMeSpacing.md),
            Text(
              'MOST RELEVANT GUIDANCE',
              style: text.labelSmall?.copyWith(letterSpacing: 1.2),
            ),
            const SizedBox(height: ForeSeeMeSpacing.sm),
            for (final item in guidance) ...[
              _GuidanceRow(item: item),
              const SizedBox(height: ForeSeeMeSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

/// A driver row: a direction icon (shape, not colour alone), the human label,
/// and a magnitude bar. The whole row is announced as one sentence.
class _DriverRow extends StatelessWidget {
  final EnvironmentalDriver driver;
  final double maxMagnitude;
  const _DriverRow({required this.driver, required this.maxMagnitude});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final increases = driver.direction == ContributionDirection.increases;
    final color = increases ? palette.error : palette.success;
    final icon = increases
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    final fraction = maxMagnitude <= 0 ? 0.0 : driver.magnitude / maxMagnitude;
    final verb = increases ? 'raising' : 'easing';

    return Semantics(
      excludeSemantics: true,
      label: '${driver.label}: $verb this estimate.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: ForeSeeMeSpacing.sm),
              Expanded(
                child: Text(
                  driver.label,
                  style: context.fsmText.bodyLarge?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => ClipRRect(
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
              child: Stack(
                children: [
                  Container(height: 8, color: palette.outlineVariant),
                  Container(
                    height: 8,
                    width: constraints.maxWidth * fraction,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidanceRow extends StatelessWidget {
  final PrioritizedRecommendation item;
  const _GuidanceRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final accent = palette.secondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.rank == 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Most relevant',
              style: text.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Text(
          item.recommendation.text,
          style: text.bodyLarge?.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 13, color: palette.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Source: ${item.recommendation.source}',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
