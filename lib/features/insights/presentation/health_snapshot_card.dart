import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/app_skeleton.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_journey_provider.dart';

/// Compact "how am I doing" summary for the Home dashboard (Sprint UX-08).
///
/// Deliberately narrow in scope: it recomputes nothing. Streaks come from the
/// existing [adherenceInsightsProvider]; this week's adherence percent and its
/// trend vs. last week come from the same [adherenceJourneyProvider] the
/// Adherence Journey screen and the Today's Mission card already watch. It
/// replaces the old four-stat-card [AdherenceInsightsCard] footprint on Home
/// with a single tappable row that opens the full journey for detail.
class HealthSnapshotCard extends ConsumerWidget {
  const HealthSnapshotCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).value?.uid ?? '';
    final insightsAsync = ref.watch(adherenceInsightsProvider);
    final journeyAsync = ref.watch(adherenceJourneyProvider(uid));

    if (insightsAsync.isLoading || journeyAsync.isLoading) {
      return const _SnapshotShell(
        child: AppSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 18, height: 18, radius: 6),
                  SizedBox(width: 8),
                  SkeletonBar(width: 120, height: 12),
                ],
              ),
              SizedBox(height: 18),
              SkeletonBar(width: double.infinity, height: 36),
              SizedBox(height: 14),
              SkeletonBar(width: 200, height: 12),
            ],
          ),
        ),
      );
    }

    // A transient failure on either signal hides the card rather than
    // breaking the dashboard — the same "degrade to nothing" rule every other
    // dashboard card already follows.
    final insights = insightsAsync.value;
    final reflection = journeyAsync.value?.reflection;
    if (insights == null || reflection == null) {
      return const SizedBox.shrink();
    }

    return _SnapshotContent(insights: insights, reflection: reflection);
  }
}

class _SnapshotContent extends StatelessWidget {
  const _SnapshotContent({required this.insights, required this.reflection});

  final AdherenceInsights insights;
  final WeeklyReflection reflection;

  static String _days(int n) => n == 1 ? '1 day' : '$n days';

  (String, Color, IconData) _trend(BuildContext context) {
    final delta = reflection.comparedToLastWeek;
    if (delta > 0) {
      return (
        'Improving',
        context.fsmColors.success,
        Icons.trending_up_rounded,
      );
    }
    if (delta < 0) {
      return ('Declining', context.fsmPalette.error, Icons.trending_down_rounded);
    }
    return ('Steady', context.fsmPalette.textSecondary, Icons.trending_flat_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final (trendLabel, trendColor, trendIcon) = _trend(context);

    void openJourney() => context.push('/adherence-history');

    return Semantics(
      button: true,
      container: true,
      label:
          'Health snapshot. Current streak ${insights.currentStreakDays} days. '
          'Best streak ${insights.longestStreakDays} days. '
          '${reflection.adherencePercent} percent adherence, $trendLabel. '
          '${insights.supportiveMessage} Opens your Adherence Journey.',
      onTap: openJourney,
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: openJourney,
          child: _SnapshotShell(
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
                      'HEALTH SNAPSHOT',
                      style: text.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: palette.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _stat(
                        context,
                        label: 'Current Streak',
                        value: _days(insights.currentStreakDays),
                      ),
                    ),
                    Expanded(
                      child: _stat(
                        context,
                        label: 'Best Streak',
                        value: _days(insights.longestStreakDays),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _stat(
                        context,
                        label: 'Adherence',
                        value: '${reflection.adherencePercent}%',
                      ),
                    ),
                    Expanded(
                      child: _stat(
                        context,
                        label: 'Trend',
                        value: trendLabel,
                        valueColor: trendColor,
                        icon: trendIcon,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: palette.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  insights.supportiveMessage,
                  style: text.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
    IconData? icon,
  }) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: valueColor ?? palette.textPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor ?? palette.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared glass shell matching the risk/insights surfaces.
class _SnapshotShell extends StatelessWidget {
  const _SnapshotShell({required this.child});
  final Widget child;

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
