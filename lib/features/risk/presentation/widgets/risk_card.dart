import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// The dashboard's primary at-a-glance signal: the user's current city risk,
/// bound live to [currentCityRiskProvider].
///
/// Renders every state — loading (skeleton), data, empty ("no risk data yet"),
/// and error/offline (retry) — and applies the grey uncertainty treatment when
/// the estimate is low-confidence. Risk is always shown with a label + icon, so
/// it is never conveyed by colour alone.
class RiskCard extends ConsumerWidget {
  const RiskCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riskAsync = ref.watch(currentCityRiskProvider);

    return riskAsync.when(
      loading: () => const _RiskCardSkeleton(),
      error: (_, _) => _RiskCardError(
        onRetry: () {
          ref.invalidate(userCityProvider);
          ref.invalidate(currentCityRiskProvider);
        },
      ),
      data: (estimate) {
        if (estimate == null) {
          return _RiskCardEmpty(city: ref.watch(userCityProvider).value);
        }
        return _RiskCardData(estimate: estimate);
      },
    );
  }
}

// ── Shared shell ──────────────────────────────────────────────────────────────

/// Rounded card surface with an optional risk-tinted gradient + ambient glow.
class _CardShell extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final Gradient? gradient;
  final Color? glowColor;

  const _CardShell({
    required this.child,
    required this.borderColor,
    this.gradient,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: gradient,
          color: gradient == null ? AppColorsV2.glassFill : null,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 44,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (glowColor != null)
              Positioned(
                top: -44,
                right: -30,
                child: IgnorePointer(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          glowColor!.withValues(alpha: 0.30),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.72],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(padding: const EdgeInsets.all(20), child: child),
          ],
        ),
      ),
    );
  }
}

// ── Data state ────────────────────────────────────────────────────────────────

class _RiskCardData extends StatelessWidget {
  final RiskEstimateModel estimate;

  const _RiskCardData({required this.estimate});

  @override
  Widget build(BuildContext context) {
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
      child: _CardShell(
        borderColor: a.border,
        gradient: LinearGradient(
          colors: [a.fill, Colors.white.withValues(alpha: 0.04)],
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
        ),
        glowColor: a.color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${estimate.city} · Today'.toUpperCase(),
                        style: AppTextStylesV2.microLabel,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(a.icon, color: a.color, size: 24),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              a.headline,
                              style: AppTextStylesV2.headline.copyWith(
                                color: a.color,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _subtitle(estimate),
                        style: AppTextStylesV2.body.copyWith(
                          color: AppColorsV2.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: RiskTrendBadge(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: AppColorsV2.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$confidencePct% confidence · updated '
                    '${_ageLabel(estimate.generatedAt)}',
                    style: AppTextStylesV2.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary line under the headline. Low-confidence estimates flag uncertainty
/// rather than a (derived) driver, since the classification is unreliable.
String _subtitle(RiskEstimateModel e) {
  if (e.lowConfidence) return '${e.disease} · low confidence';
  return '${e.disease} · ${_dominantDriverLabel(e)} driver';
}

/// Surfaces whichever environmental signal is most elevated on a coarse
/// reference scale. This is a presentational heuristic over the estimate's own
/// feature values — not an additional clinical claim, and it never alters the
/// frozen contract.
String _dominantDriverLabel(RiskEstimateModel e) {
  final aqiN = (e.aqi / 300).clamp(0.0, 2.0);
  final tempN = ((e.temperature - 10) / 30).clamp(0.0, 2.0);
  final humN = (e.humidity / 100).clamp(0.0, 2.0);
  if (aqiN >= tempN && aqiN >= humN) return 'Air quality';
  if (tempN >= humN) return 'Heat';
  return 'Humidity';
}

/// Human-friendly age of an estimate ("just now" / "3h ago" / "2 days ago").
String _ageLabel(DateTime generatedAt) {
  final diff = DateTime.now().toUtc().difference(generatedAt.toUtc());
  if (diff.inMinutes < 60) {
    return diff.inMinutes <= 1 ? 'just now' : '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _RiskCardEmpty extends StatelessWidget {
  final String? city;

  const _RiskCardEmpty({required this.city});

  @override
  Widget build(BuildContext context) {
    final where = (city != null && city!.isNotEmpty) ? city! : 'your city';
    return _CardShell(
      borderColor: AppColorsV2.stroke,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColorsV2.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.monitor_heart_outlined,
              color: AppColorsV2.violet,
              size: 22,
            ),
          ),
          const SizedBox(height: 14),
          Text('No risk data yet', style: AppTextStylesV2.cardTitle),
          const SizedBox(height: 6),
          Text(
            "We don't have an environmental risk estimate for $where this "
            'week. New estimates arrive weekly — check back soon.',
            style: AppTextStylesV2.body,
          ),
        ],
      ),
    );
  }
}

// ── Error / offline state ─────────────────────────────────────────────────────

class _RiskCardError extends StatelessWidget {
  final VoidCallback onRetry;

  const _RiskCardError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      borderColor: RiskVisuals.high.border,
      gradient: LinearGradient(
        colors: [
          AppColorsV2.riskHigh.withValues(alpha: 0.08),
          AppColorsV2.glassFill,
        ],
        begin: const Alignment(-0.6, -1),
        end: const Alignment(0.6, 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppColorsV2.riskHigh,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text("Couldn't load risk", style: AppTextStylesV2.cardTitle),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You may be offline. Pull the latest when your connection is back.',
            style: AppTextStylesV2.body,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColorsV2.teal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: AppColorsV2.teal.withValues(alpha: 0.4),
                  ),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _RiskCardSkeleton extends StatelessWidget {
  const _RiskCardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return _CardShell(
      borderColor: AppColorsV2.stroke,
      child: Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(120, 12),
            const SizedBox(height: 14),
            bar(180, 28),
            const SizedBox(height: 14),
            bar(220, 12),
            const SizedBox(height: 10),
            bar(140, 12),
          ],
        ),
      ),
    );
  }
}
