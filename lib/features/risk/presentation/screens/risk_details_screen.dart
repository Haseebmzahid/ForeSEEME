import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_driver_service.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_trend_chart.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// Premium Risk Details analytics screen (matches `docs/ui sprint 3/Risk
/// details.png`). Pure presentation — composes existing providers only
/// ([currentCityRiskProvider], [currentCityRiskHistoryProvider],
/// [riskTrendProvider], [currentRecommendationProvider]); no Firestore, no
/// business logic here. Historical points are real Firestore estimates —
/// never fabricated; too little history degrades to an informative empty state.
class RiskDetailsScreen extends ConsumerWidget {
  const RiskDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riskAsync = ref.watch(currentCityRiskProvider);

    return Scaffold(
      backgroundColor: AppColorsV2.shell,
      appBar: AppBar(
        backgroundColor: AppColorsV2.shell,
        elevation: 0,
        foregroundColor: AppColorsV2.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Risk Details', style: AppTextStylesV2.cardTitle),
      ),
      body: SafeArea(
        child: riskAsync.when(
          loading: () => const _DetailsSkeleton(),
          error: (_, _) => _ErrorView(
            onRetry: () {
              ref.invalidate(userCityProvider);
              ref.invalidate(currentCityRiskProvider);
            },
          ),
          data: (estimate) => estimate == null
              ? const _NoRiskView()
              : _Content(estimate: estimate),
        ),
      ),
    );
  }
}

// ── Content ────────────────────────────────────────────────────────────────--

class _Content extends ConsumerWidget {
  final RiskEstimateModel estimate;
  const _Content({required this.estimate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _HeroCard(estimate: estimate),
        const SizedBox(height: 18),
        const _TrendChartCard(),
        const SizedBox(height: 18),
        _AnalyticsRow(estimate: estimate),
        const SizedBox(height: 18),
        const _WhatYouCanDoCard(),
      ],
    );
    if (reduceMotion) return content;

    // Gentle fade + rise on open (respects reduced-motion above).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

// ── Hero ───────────────────────────────────────────────────────────────────--

class _HeroCard extends ConsumerWidget {
  final RiskEstimateModel estimate;
  const _HeroCard({required this.estimate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = RiskVisuals.of(
      estimate.riskLevel,
      lowConfidence: estimate.lowConfidence,
    );
    final confidencePct = (estimate.confidence * 100).round();

    return Semantics(
      container: true,
      label:
          '${estimate.city} risk: ${a.headline}, ${estimate.disease}, '
          '$confidencePct percent confidence',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [a.fill, Colors.white.withValues(alpha: 0.03)],
              begin: const Alignment(-0.6, -1),
              end: const Alignment(0.5, 1),
            ),
            border: Border.all(color: a.border),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -20,
                child: IgnorePointer(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          a.color.withValues(alpha: 0.26),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.72],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                child: Column(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: a.color.withValues(alpha: 0.16),
                        border: Border.all(
                          color: a.color.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Icon(a.icon, color: a.color, size: 30),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      a.headline,
                      style: AppTextStylesV2.headline.copyWith(
                        color: a.color,
                        fontSize: 30,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${estimate.city} · ${estimate.disease}',
                      style: AppTextStylesV2.body.copyWith(
                        color: AppColorsV2.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        const RiskTrendBadge(),
                        _ConfidenceBadge(percent: confidencePct),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final int percent;
  const _ConfidenceBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$percent percent confidence',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColorsV2.textSecondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColorsV2.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 13,
              color: AppColorsV2.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              '$percent% confidence',
              style: AppTextStylesV2.caption.copyWith(
                color: AppColorsV2.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Trend chart card ──────────────────────────────────────────────────────--

class _TrendChartCard extends ConsumerWidget {
  const _TrendChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(currentCityRiskHistoryProvider);
    final trend =
        ref.watch(riskTrendProvider).value ?? TrendDirection.insufficient;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('RISK TREND', style: AppTextStylesV2.microLabel),
              const Spacer(),
              Text(
                'Risk index',
                style: AppTextStylesV2.caption.copyWith(
                  color: AppColorsV2.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          historyAsync.when(
            loading: () => const _ChartSkeleton(),
            error: (_, _) => _ChartError(
              onRetry: () => ref.invalidate(currentCityRiskHistoryProvider),
            ),
            data: (history) {
              if (history.length < 2) return const _NoTrendView();
              final ordered = [...history]
                ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
              final color = RiskVisuals.of(
                ordered.last.riskLevel,
                lowConfidence: ordered.last.lowConfidence,
              ).color;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TrendSummary(direction: trend, spanText: _spanText(ordered)),
                  const SizedBox(height: 8),
                  RiskTrendChart(history: ordered, color: color),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _spanText(List<RiskEstimateModel> ordered) {
    final days = ordered.last.generatedAt
        .difference(ordered.first.generatedAt)
        .inDays;
    if (days >= 14) return 'last ${(days / 7).round()} weeks';
    if (days >= 1) return 'last $days days';
    return 'recent estimates';
  }
}

class _TrendSummary extends StatelessWidget {
  final TrendDirection direction;
  final String spanText;
  const _TrendSummary({required this.direction, required this.spanText});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String verb) = switch (direction) {
      TrendDirection.rising => (
        Icons.trending_up_rounded,
        AppColorsV2.riskHigh,
        'Rising',
      ),
      TrendDirection.falling => (
        Icons.trending_down_rounded,
        AppColorsV2.riskLow,
        'Improving',
      ),
      TrendDirection.stable => (
        Icons.trending_flat_rounded,
        AppColorsV2.riskMedium,
        'Stable',
      ),
      TrendDirection.insufficient => (
        Icons.remove_rounded,
        AppColorsV2.riskUncertain,
        'Not enough data',
      ),
    };

    final text = direction == TrendDirection.insufficient
        ? verb
        : '$verb over the $spanText';

    return Semantics(
      label: 'Trend: $text',
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              style: AppTextStylesV2.body.copyWith(
                color: AppColorsV2.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Informative empty state — shown instead of an empty chart when there are
/// fewer than two real historical estimates.
class _NoTrendView extends StatelessWidget {
  const _NoTrendView();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.show_chart_rounded,
              size: 44,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'No historical trend available yet.',
              style: AppTextStylesV2.body.copyWith(
                color: AppColorsV2.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'A trend appears once a few weekly estimates have been recorded '
              'for your city.',
              style: AppTextStylesV2.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartError extends StatelessWidget {
  final VoidCallback onRetry;
  const _ChartError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(height: 10),
            Text("Couldn't load the trend", style: AppTextStylesV2.body),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColorsV2.teal,
                side: BorderSide(
                  color: AppColorsV2.teal.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Analytics cards (primary driver + confidence) ────────────────────────────

class _AnalyticsRow extends StatelessWidget {
  final RiskEstimateModel estimate;
  const _AnalyticsRow({required this.estimate});

  @override
  Widget build(BuildContext context) {
    final driver = dominantDriver(estimate);
    final confidencePct = (estimate.confidence * 100).round();

    // IntrinsicHeight bounds the Row height so the two equal-width cards match
    // heights (their inner Columns are mainAxisSize.max).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _AnalyticsCard(
              icon: _driverIcon(driver.kind),
              iconColor: AppColorsV2.blue,
              label: 'Primary driver',
              value: driver.label,
              detail: driver.value,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _AnalyticsCard(
              icon: Icons.verified_outlined,
              iconColor: AppColorsV2.teal,
              label: 'Confidence',
              value: '$confidencePct%',
            ),
          ),
        ],
      ),
    );
  }

  IconData _driverIcon(RiskDriverKind kind) => switch (kind) {
    RiskDriverKind.airQuality => Icons.air_rounded,
    RiskDriverKind.heat => Icons.thermostat_rounded,
    RiskDriverKind.humidity => Icons.water_drop_outlined,
  };
}

class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? detail;

  const _AnalyticsCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: detail != null ? '$label: $value $detail' : '$label: $value',
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTextStylesV2.microLabel),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: AppTextStylesV2.cardTitle.copyWith(fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· $detail',
                    style: AppTextStylesV2.body.copyWith(
                      color: AppColorsV2.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── What you can do (cited recommendation, existing provider) ────────────────

class _WhatYouCanDoCard extends ConsumerWidget {
  const _WhatYouCanDoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(currentRecommendationProvider);
    return async.when(
      loading: () => const _ChartSkeleton(height: 96),
      error: (_, _) => const SizedBox.shrink(),
      data: (rec) => _RecommendationCard(recommendation: rec),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final HealthRecommendation recommendation;
  const _RecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColorsV2.teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.teal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: 18,
                color: AppColorsV2.teal,
              ),
              const SizedBox(width: 8),
              Text(
                'What you can do',
                style: AppTextStylesV2.cardTitle.copyWith(
                  color: AppColorsV2.teal,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            recommendation.text,
            style: AppTextStylesV2.body.copyWith(
              color: AppColorsV2.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
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
                  'Source: ${recommendation.source}',
                  style: AppTextStylesV2.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared shell + skeleton + full-screen states ─────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: child,
    );
  }
}

class _ChartSkeleton extends StatelessWidget {
  final double height;
  const _ChartSkeleton({this.height = 172});

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: SkeletonBox(height: height, radius: 14),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h) => Container(
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
    );

    return SingleChildScrollView(
      // Scrollable so the skeleton never overflows a short viewport (responsive).
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.13),
        child: Column(
          children: [
            box(190),
            const SizedBox(height: 18),
            box(230),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: box(104)),
                const SizedBox(width: 14),
                Expanded(child: box(104)),
              ],
            ),
            const SizedBox(height: 18),
            box(120),
          ],
        ),
      ),
    );
  }
}

class _NoRiskView extends StatelessWidget {
  const _NoRiskView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.monitor_heart_outlined,
              size: 56,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(height: 18),
            Text('No risk data yet', style: AppTextStylesV2.cardTitle),
            const SizedBox(height: 8),
            Text(
              "We don't have an environmental risk estimate for your city this "
              'week. New estimates arrive weekly — check back soon.',
              style: AppTextStylesV2.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AppColorsV2.textTertiary,
            ),
            const SizedBox(height: 18),
            Text(
              "Couldn't load risk details",
              style: AppTextStylesV2.cardTitle,
            ),
            const SizedBox(height: 8),
            Text(
              'You may be offline. Try again when your connection is back.',
              style: AppTextStylesV2.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColorsV2.teal,
                side: BorderSide(
                  color: AppColorsV2.teal.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
