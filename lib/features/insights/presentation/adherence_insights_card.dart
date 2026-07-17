import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';

/// Dashboard card surfacing **supportive** adherence insights (Prompt 7).
///
/// Pure presentation: it only watches [adherenceInsightsProvider] and renders the
/// computed [AdherenceInsights]. Deliberately encouraging — it shows streaks and
/// strengths and a gentle nudge, never a grade, percentage score, or blame. On
/// error it hides so a transient failure never breaks the dashboard.
class AdherenceInsightsCard extends ConsumerWidget {
  const AdherenceInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adherenceInsightsProvider);

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
                  SkeletonBar(width: 130, height: 12),
                ],
              ),
              SizedBox(height: 16),
              SkeletonBox(height: 12, radius: 6),
              SizedBox(height: 8),
              SkeletonBar(width: 200, height: 12),
            ],
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (insights) => _InsightsContent(insights: insights),
    );
  }
}

class _InsightsContent extends StatelessWidget {
  final AdherenceInsights insights;
  const _InsightsContent({required this.insights});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.favorite_outline_rounded,
                size: 18,
                color: palette.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'ADHERENCE INSIGHTS',
                style: text.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insights.headline,
            style: text.titleMedium?.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(
            insights.supportiveMessage,
            style: text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (insights.hasData) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatChip(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Current streak',
                  value: _days(insights.currentStreakDays),
                ),
                _StatChip(
                  icon: Icons.emoji_events_outlined,
                  label: 'Best streak',
                  value: _days(insights.longestStreakDays),
                ),
                _StatChip(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Doses taken',
                  value: '${insights.takenCount}',
                ),
                if (insights.strongestBucket != null)
                  _StatChip(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Most consistent',
                    value: insights.strongestBucket!.label,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _days(int n) => n == 1 ? '1 day' : '$n days';
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: palette.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: text.labelSmall?.copyWith(
                  fontSize: 10,
                  color: palette.textTertiary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: text.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
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
