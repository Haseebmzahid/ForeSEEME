import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/confidence_meter.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_override_notice.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_visuals.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/staleness_indicator.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/trend_badge.dart';

/// The dashboard's primary at-a-glance signal: the user's current city risk,
/// bound live to [currentCityRiskProvider].
///
/// Renders every state — loading (skeleton), data, empty ("no risk data yet"),
/// and error/offline (retry) — and applies the neutral uncertainty treatment
/// when the estimate is low-confidence. Risk is always shown with a label +
/// icon, so it is never conveyed by colour alone.
class RiskCard extends ConsumerWidget {
  const RiskCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riskAsync = ref.watch(currentCityRiskProvider);
    // An active operator override (Prompt 13) transparently supersedes the model
    // estimate on this at-a-glance surface. `.asData?.value` is null while it
    // loads / on error / when none is active, so the normal path is unaffected.
    final override = ref.watch(currentCityOverrideProvider).asData?.value;

    return riskAsync.when(
      loading: () => const _RiskCardSkeleton(),
      error: (_, _) => override != null
          ? _RiskCardOverride(riskOverride: override)
          : _RiskCardError(
              onRetry: () {
                ref.invalidate(userCityProvider);
                ref.invalidate(currentCityRiskProvider);
              },
            ),
      data: (estimate) {
        if (override != null) {
          return _RiskCardOverride(
            riskOverride: override,
            modelEstimate: estimate,
          );
        }
        if (estimate == null) {
          return _RiskCardEmpty(city: ref.watch(userCityProvider).value);
        }
        return _RiskCardData(estimate: estimate);
      },
    );
  }
}

// ── Override state (operator-set risk, clearly labelled) ─────────────────────

class _RiskCardOverride extends StatelessWidget {
  final RiskOverride riskOverride;
  final RiskEstimateModel? modelEstimate;

  const _RiskCardOverride({required this.riskOverride, this.modelEstimate});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final a = RiskVisuals.resolve(context, riskOverride.riskLevel);
    final violet = palette.tertiary;

    return Semantics(
      container: true,
      label:
          'Operator-set risk for ${riskOverride.city}: ${a.headline}, '
          '${riskOverride.disease}. Reason: ${riskOverride.reason}',
      child: _CardShell(
        borderColor: violet.withValues(alpha: 0.4),
        gradient: LinearGradient(
          colors: [violet.withValues(alpha: 0.12), a.fill],
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
        ),
        glowColor: a.color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${riskOverride.city} · Today'.toUpperCase(),
                  style: _microLabel(context),
                ),
                const Spacer(),
                const OverrideBadge(),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(a.icon, color: a.color, size: 24),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    a.headline,
                    style: text.displaySmall?.copyWith(
                      fontSize: 26,
                      color: a.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${riskOverride.disease} · set manually by an operator',
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notes_rounded,
                  size: 13,
                  color: palette.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    riskOverride.reason,
                    style: text.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
            if (modelEstimate != null) ...[
              const SizedBox(height: 6),
              Text(
                'Automated model estimate: '
                '${RiskVisuals.of(modelEstimate!.riskLevel, lowConfidence: modelEstimate!.lowConfidence).headline}',
                style: text.bodySmall?.copyWith(color: palette.textTertiary),
              ),
            ],
          ],
        ),
      ),
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
    // Reduced-transparency fallback: neutral cards use an opaque fill and the
    // low-contrast ambient glow is dropped (audit M4).
    final reduceTransparency = A11y.reduceTransparency(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: gradient,
          color: gradient == null ? ForeSeeMeSurface.fill(context) : null,
          border: Border.all(color: borderColor),
          boxShadow: context.fsmColors.shadows.strong,
        ),
        child: Stack(
          children: [
            if (glowColor != null && !reduceTransparency)
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

/// Uppercase tracked micro-label used across the risk card.
TextStyle? _microLabel(BuildContext context) =>
    context.fsmText.labelSmall?.copyWith(
      letterSpacing: 1.2,
      color: context.fsmPalette.textTertiary,
    );

// ── Data state ────────────────────────────────────────────────────────────────

class _RiskCardData extends StatelessWidget {
  final RiskEstimateModel estimate;

  const _RiskCardData({required this.estimate});

  @override
  Widget build(BuildContext context) {
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
      child: _CardShell(
        borderColor: a.border,
        gradient: LinearGradient(
          colors: [a.fill, ForeSeeMeSurface.fill(context)],
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
                        style: _microLabel(context),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(a.icon, color: a.color, size: 24),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              a.headline,
                              style: text.displaySmall?.copyWith(
                                fontSize: 26,
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
                        style: text.bodyMedium?.copyWith(
                          color: palette.textSecondary,
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
                  color: palette.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$confidencePct% confidence · updated '
                    '${riskAgeLabel(estimate.generatedAt)}',
                    style: text.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ),
                ConfidenceMeter(confidence: estimate.confidence, width: 56),
              ],
            ),
            // Shared, self-guarding staleness notice (centralised threshold +
            // visual): renders only when the estimate is out of date.
            RiskStalenessNotice(generatedAt: estimate.generatedAt),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _RiskCardEmpty extends StatelessWidget {
  final String? city;

  const _RiskCardEmpty({required this.city});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final violet = palette.tertiary;
    final where = (city != null && city!.isNotEmpty) ? city! : 'your city';
    return _CardShell(
      borderColor: ForeSeeMeSurface.stroke(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.monitor_heart_outlined,
              color: violet,
              size: 22,
            ),
          ),
          const SizedBox(height: 14),
          Text('No risk data yet', style: text.titleLarge),
          const SizedBox(height: 6),
          Text(
            "We don't have an environmental risk estimate for $where this "
            'week. New estimates arrive weekly — check back soon.',
            style: text.bodyMedium?.copyWith(color: palette.textSecondary),
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
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final error = palette.error;
    return _CardShell(
      borderColor: RiskVisuals.resolve(context, RiskLevel.high).border,
      gradient: LinearGradient(
        colors: [error.withValues(alpha: 0.08), ForeSeeMeSurface.fill(context)],
        begin: const Alignment(-0.6, -1),
        end: const Alignment(0.6, 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: error, size: 22),
              const SizedBox(width: 10),
              Text("Couldn't load risk", style: text.titleLarge),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You may be offline. Pull the latest when your connection is back.',
            style: text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: palette.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: palette.primary.withValues(alpha: 0.4),
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
    return _CardShell(
      borderColor: ForeSeeMeSurface.stroke(context),
      child: const AppSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBar(width: 120, height: 12),
            SizedBox(height: 14),
            SkeletonBar(width: 180, height: 28),
            SizedBox(height: 14),
            SkeletonBar(width: 220, height: 12),
            SizedBox(height: 10),
            SkeletonBar(width: 140, height: 12),
          ],
        ),
      ),
    );
  }
}
