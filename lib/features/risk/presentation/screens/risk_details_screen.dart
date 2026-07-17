import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/core/widgets/error_state.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/core/widgets/offline_state.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_driver_service.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/confidence_meter.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/environment_tiles.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/explanation_panel.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_override_notice.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_surface.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_trend_chart.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/staleness_indicator.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// Premium Risk Details analytics screen. Pure presentation — composes existing
/// providers only ([currentCityRiskProvider], [currentCityRiskHistoryProvider],
/// [riskTrendProvider], [currentRecommendationProvider]); no Firestore, no
/// business logic here. Historical points are real Firestore estimates —
/// never fabricated; too little history degrades to an informative empty state.
class RiskDetailsScreen extends ConsumerWidget {
  const RiskDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final riskAsync = ref.watch(currentCityRiskProvider);
    // An active operator override (Prompt 13) is surfaced as a prominent banner
    // above the model detail — never applied silently.
    final override = ref.watch(currentCityOverrideProvider).asData?.value;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Risk Details', style: context.fsmText.titleLarge),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AppMotion.stateSwitcher(
                context,
                riskAsync.when(
                  loading: () => const _DetailsSkeleton(),
                  error: (error, _) {
                    void retry() {
                      ref.invalidate(userCityProvider);
                      ref.invalidate(currentCityRiskProvider);
                    }

                    // Connectivity loss and server errors are separate states.
                    return isOfflineError(error)
                        ? OfflineState(onRetry: retry)
                        : ErrorState(
                            title: "Couldn't load risk details",
                            explanation:
                                'Something went wrong loading this. Please try again.',
                            onRetry: retry,
                            detail: '$error',
                          );
                  },
                  data: (estimate) {
                    final body = estimate == null
                        ? const EmptyState(
                            icon: Icons.monitor_heart_outlined,
                            title: 'No risk data yet',
                            description:
                                "We don't have an environmental risk estimate for your "
                                'city this week. New estimates arrive weekly — check '
                                'back soon.',
                          )
                        : _Content(estimate: estimate);
                    if (override == null) return body;
                    // Operator override active: lead with the transparency banner, keep
                    // the automated model detail (labelled) below it.
                    return _OverriddenBody(
                      riskOverride: override,
                      modelEstimate: estimate,
                      child: body,
                    );
                  },
                ),
              ),
            ),
            // Persistent non-diagnostic framing — always shown, independent of
            // the risk data state (loading / error / empty / data).
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: MedicalDisclaimer.banner(),
            ),
          ],
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
        // Honest staleness label right beside the "current risk" headline —
        // shared, self-guarding widget (renders only when out of date, so a
        // fresh estimate leaves the layout unchanged).
        RiskStalenessNotice(generatedAt: estimate.generatedAt, topGap: 18),
        // High risk → surface one-tap emergency help immediately (reuses the
        // Sprint 3 emergency contact + dialer).
        if (estimate.riskLevel == RiskLevel.high) ...[
          const SizedBox(height: 18),
          const _EmergencyAffordance(),
        ],
        // Genuine, model-derived "why this prediction" + confidence rationale
        // (Sprint 5, Prompt 6) — the trust surface, placed high.
        const SizedBox(height: 18),
        const ExplanationPanel(),
        const SizedBox(height: 18),
        const _TrendChartCard(),
        const SizedBox(height: 18),
        EnvironmentTiles(estimate: estimate),
        const SizedBox(height: 14),
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

// ── Operator override overlay (transparency banner + model detail) ───────────

/// Wraps the normal Risk Details body with a prominent [RiskOverrideNotice]
/// banner when an operator override is active, so the override is unmissable
/// while the automated model's detail remains visible (and labelled) below.
class _OverriddenBody extends StatelessWidget {
  final RiskOverride riskOverride;
  final RiskEstimateModel? modelEstimate;
  final Widget child;

  const _OverriddenBody({
    required this.riskOverride,
    required this.modelEstimate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: RiskOverrideNotice(
            riskOverride: riskOverride,
            modelEstimate: modelEstimate,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

// ── Emergency affordance (high risk only) ────────────────────────────────────

/// One-tap emergency dial shown on the Risk Details screen when the current
/// estimate is High. Reuses the Sprint 3 emergency contact + [EmergencyCard] +
/// [launcherServiceProvider] — no new content, no medical text generated.
class _EmergencyAffordance extends ConsumerWidget {
  const _EmergencyAffordance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(emergencyContactProvider);
    return EmergencyCard(
      contact: contact,
      onCall: () => ref.read(launcherServiceProvider).dialPhone(contact.number),
    );
  }
}

// ── Hero ───────────────────────────────────────────────────────────────────--

class _HeroCard extends ConsumerWidget {
  final RiskEstimateModel estimate;
  const _HeroCard({required this.estimate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final a = RiskVisuals.resolve(
      context,
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
              colors: [a.fill, RiskSurface.fill(context)],
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
                      style: text.displaySmall?.copyWith(
                        color: a.color,
                        fontSize: 30,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${estimate.city} · ${estimate.disease}',
                      style: text.bodyMedium?.copyWith(
                        color: palette.textSecondary,
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
                    const SizedBox(height: 10),
                    ConfidenceMeter(confidence: estimate.confidence),
                    const SizedBox(height: 12),
                    // When the estimate was generated — transparent about
                    // recency so the headline is never read as "right now".
                    Text(
                      'Updated ${riskAgeLabel(estimate.generatedAt)}',
                      style: text.bodySmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                      textAlign: TextAlign.center,
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
    final palette = context.fsmPalette;
    return Semantics(
      label: '$percent percent confidence',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.textSecondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: palette.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_outlined,
              size: 13,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              '$percent% confidence',
              style: context.fsmText.bodySmall?.copyWith(
                color: palette.textSecondary,
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
    final palette = context.fsmPalette;
    final historyAsync = ref.watch(currentCityRiskHistoryProvider);
    final trend =
        ref.watch(riskTrendProvider).value ?? TrendDirection.insufficient;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'RISK TREND',
                style: context.fsmText.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: palette.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                'Risk index',
                style: context.fsmText.bodySmall?.copyWith(
                  color: palette.textTertiary,
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
              final color = RiskVisuals.colorOf(
                context,
                ordered.last.riskLevel,
                lowConfidence: ordered.last.lowConfidence,
              );
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
    final palette = context.fsmPalette;
    final colors = context.fsmColors;
    final (IconData icon, Color color, String verb) = switch (direction) {
      TrendDirection.rising => (
        Icons.trending_up_rounded,
        palette.error,
        'Rising',
      ),
      TrendDirection.falling => (
        Icons.trending_down_rounded,
        colors.success,
        'Improving',
      ),
      TrendDirection.stable => (
        Icons.trending_flat_rounded,
        colors.warning,
        'Stable',
      ),
      TrendDirection.insufficient => (
        Icons.remove_rounded,
        palette.onSurfaceVariant,
        'Not enough data',
      ),
    };

    final label = direction == TrendDirection.insufficient
        ? verb
        : '$verb over the $spanText';

    return Semantics(
      label: 'Trend: $label',
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: context.fsmText.bodyMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return SizedBox(
      height: 172,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 44,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'No historical trend available yet.',
              style: text.bodyMedium?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'A trend appears once a few weekly estimates have been recorded '
              'for your city.',
              style: text.bodySmall?.copyWith(color: palette.textTertiary),
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
    final palette = context.fsmPalette;
    return SizedBox(
      height: 172,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 10),
            Text("Couldn't load the trend", style: context.fsmText.bodyMedium),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: palette.primary,
                side: BorderSide(
                  color: palette.primary.withValues(alpha: 0.4),
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
              iconColor: context.fsmColors.info,
              label: 'Primary driver',
              value: driver.label,
              detail: driver.value,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _AnalyticsCard(
              icon: Icons.verified_outlined,
              iconColor: context.fsmPalette.primary,
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
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
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: text.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: palette.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: text.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· $detail',
                    style: text.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final primary = palette.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 18,
                color: primary,
              ),
              const SizedBox(width: 8),
              Text(
                'What you can do',
                style: text.titleMedium?.copyWith(color: primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            recommendation.text,
            style: text.bodyMedium?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 13,
                color: palette.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Source: ${recommendation.source}',
                  style: text.bodySmall?.copyWith(
                    color: palette.textTertiary,
                  ),
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
    // Reduced-transparency fallback handled centrally by RiskSurface (audit M4).
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: RiskSurface.card(context),
      child: child,
    );
  }
}

class _ChartSkeleton extends StatelessWidget {
  final double height;
  const _ChartSkeleton({this.height = 172});

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(child: SkeletonBox(height: height, radius: 14));
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    // Reuses the shared AppSkeleton shimmer primitive — no bespoke shimmer here.
    return const SingleChildScrollView(
      // Scrollable so the skeleton never overflows a short viewport (responsive).
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: AppSkeleton(
        child: Column(
          children: [
            SkeletonBox(height: 190),
            SizedBox(height: 18),
            SkeletonBox(height: 230),
            SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 110)),
                SizedBox(width: 14),
                Expanded(child: SkeletonBox(height: 110)),
              ],
            ),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 104)),
                SizedBox(width: 14),
                Expanded(child: SkeletonBox(height: 104)),
              ],
            ),
            SizedBox(height: 18),
            SkeletonBox(height: 120),
          ],
        ),
      ),
    );
  }
}
