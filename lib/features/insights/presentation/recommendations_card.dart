import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/services/alert_deep_link_router.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';

/// Dashboard card surfacing the current **cited** recommendation (Prompt 6).
///
/// Pure presentation: it only watches [currentRecommendationProvider] and
/// renders the looked-up advisory — it never composes medical text (Rule 11).
/// Every state shows the source and an escalation-to-help line. On loading it
/// shows a compact placeholder; on error it hides (a transient failure must not
/// break the dashboard).
class RecommendationsCard extends ConsumerWidget {
  const RecommendationsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(currentRecommendationProvider);

    return async.when(
      // Content-loading (the card sits among other visible content) → an
      // in-place skeleton of the card shape, not the full-screen brand loader.
      loading: () => const _CardShell(
        child: AppSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 18, height: 18, radius: 6),
                  SizedBox(width: 8),
                  SkeletonBar(width: 150, height: 12),
                ],
              ),
              SizedBox(height: 16),
              SkeletonBox(height: 12, radius: 6),
              SizedBox(height: 8),
              SkeletonBox(height: 12, radius: 6),
              SizedBox(height: 8),
              SkeletonBar(width: 180, height: 12),
            ],
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (rec) => _RecommendationContent(recommendation: rec),
    );
  }
}

class _RecommendationContent extends StatelessWidget {
  final HealthRecommendation recommendation;
  const _RecommendationContent({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final error = palette.error;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 18,
                color: palette.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'RECOMMENDED FOR YOU',
                style: text.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recommendation.text,
            style: text.bodyMedium?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 12),
          // Escalation — always routes to professional/emergency help.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.xs),
              border: Border.all(color: error.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.emergency_outlined, size: 15, color: error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recommendation.escalation,
                    style: text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
              _LearnMoreButton(deepLink: recommendation.deepLink),
            ],
          ),
        ],
      ),
    );
  }
}

class _LearnMoreButton extends StatelessWidget {
  final String deepLink;
  const _LearnMoreButton({required this.deepLink});

  @override
  Widget build(BuildContext context) {
    // Only offer navigation to a known in-app route (reuses the P4 whitelist).
    if (!AlertDeepLinkRouter.knownRoutes.contains(deepLink)) {
      return const SizedBox.shrink();
    }
    final toHospitals = deepLink == '/nearby-hospitals';
    return TextButton.icon(
      onPressed: () => context.push(deepLink),
      icon: Icon(
        toHospitals ? Icons.local_hospital_outlined : Icons.menu_book_outlined,
        size: 16,
      ),
      label: Text(toHospitals ? 'Find help' : 'Learn more'),
      style: TextButton.styleFrom(
        foregroundColor: context.fsmPalette.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        // Keep a ≥48px accessible tap target (Prompt 9 a11y pass).
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: context.fsmText.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shared glass shell matching the risk surfaces.
class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: ForeSeeMeSurface.card(context),
      child: child,
    );
  }
}
