import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
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
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.eco_outlined,
                size: 18,
                color: AppColorsV2.riskLow,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Environmental drivers',
                  style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          if (view.drivers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'The main factors shaping this week’s $level ${estimate.disease} '
              'estimate:',
              style: AppTextStylesV2.body,
            ),
            const SizedBox(height: 14),
            for (final driver in view.drivers) ...[
              _DriverRow(driver: driver, maxMagnitude: maxMagnitude),
              const SizedBox(height: 12),
            ],
          ],
          if (guidance.isNotEmpty) ...[
            const SizedBox(height: 2),
            const Divider(height: 1, color: AppColorsV2.stroke),
            const SizedBox(height: 14),
            Text('MOST RELEVANT GUIDANCE', style: AppTextStylesV2.microLabel),
            const SizedBox(height: 10),
            for (final item in guidance) ...[
              _GuidanceRow(item: item),
              const SizedBox(height: 10),
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
    final increases = driver.direction == ContributionDirection.increases;
    final color = increases ? AppColorsV2.riskHigh : AppColorsV2.riskLow;
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  driver.label,
                  style: AppTextStylesV2.body.copyWith(
                    color: AppColorsV2.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(height: 8, color: AppColorsV2.stroke),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.rank == 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: AppColorsV2.teal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColorsV2.teal.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Most relevant',
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.teal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Text(
          item.recommendation.text,
          style: AppTextStylesV2.body.copyWith(color: AppColorsV2.textPrimary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 13,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Source: ${item.recommendation.source}',
                style: AppTextStylesV2.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
