import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
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
      loading: () => const _CardShell(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColorsV2.teal),
                strokeWidth: 2,
              ),
            ),
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
    return _CardShell(
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
              Text('RECOMMENDED FOR YOU', style: AppTextStylesV2.microLabel),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recommendation.text,
            style: AppTextStylesV2.body.copyWith(
              color: AppColorsV2.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Escalation — always routes to professional/emergency help.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColorsV2.riskHigh.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColorsV2.riskHigh.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.emergency_outlined,
                  size: 15,
                  color: AppColorsV2.riskHigh,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recommendation.escalation,
                    style: AppTextStylesV2.caption.copyWith(
                      color: AppColorsV2.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
        foregroundColor: AppColorsV2.teal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        // Keep a ≥48px accessible tap target (Prompt 9 a11y pass).
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: AppTextStylesV2.caption.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shared glass shell matching the Sprint 3 v2 surfaces.
class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColorsV2.glassFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColorsV2.stroke),
      ),
      child: child,
    );
  }
}
