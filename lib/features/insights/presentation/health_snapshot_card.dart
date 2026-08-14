import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_palette.dart';
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
/// existing [adherenceInsightsProvider]; the daily series, this week's adherence
/// percent and its trend vs. last week come from the same
/// [adherenceJourneyProvider] the Adherence Journey screen and the Today's
/// Mission card already watch. It replaces the old four-stat-card
/// [AdherenceInsightsCard] footprint on Home with a single tappable row that
/// opens the full journey for detail.
///
/// Sprint 6 design pass: laid out as an instrument readout — a daily bar series
/// over a tracked stat row. The series is exactly as long as the journey's own
/// timeline (7 days) and is labelled with that length; it is never padded out
/// to a rounder-looking window.
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
                  SkeletonBar(width: 120, height: 10),
                  Spacer(),
                  SkeletonBar(width: 56, height: 10),
                ],
              ),
              SizedBox(height: 16),
              SkeletonBar(width: double.infinity, height: 44),
              SizedBox(height: 18),
              SkeletonBar(width: double.infinity, height: 28),
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
    final journey = journeyAsync.value;
    if (insights == null || journey == null) {
      return const SizedBox.shrink();
    }

    return _SnapshotContent(
      insights: insights,
      reflection: journey.reflection,
      timeline: journey.weeklyTimeline,
    );
  }
}

class _SnapshotContent extends StatelessWidget {
  const _SnapshotContent({
    required this.insights,
    required this.reflection,
    required this.timeline,
  });

  final AdherenceInsights insights;
  final WeeklyReflection reflection;
  final List<DayJourneyCard> timeline;

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
    final mono = context.fsmTelemetry;
    final (trendLabel, trendColor, trendIcon) = _trend(context);

    void openJourney() => context.push('/adherence-history');

    return Semantics(
      button: true,
      container: true,
      label:
          'Health snapshot, last ${timeline.length} days. '
          'Current streak ${insights.currentStreakDays} days. '
          'Best streak ${insights.longestStreakDays} days. '
          '${reflection.adherencePercent} percent adherence, $trendLabel. '
          '${insights.supportiveMessage} Opens your Adherence Journey.',
      onTap: openJourney,
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: openJourney,
          child: _SnapshotShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      // The window is named from the data's own length, not a
                      // fixed literal, so the label can never overstate it.
                      'ADHERENCE · ${timeline.length} DAYS',
                      style: mono.channel,
                    ),
                    const Spacer(),
                    Icon(trendIcon, size: 13, color: trendColor),
                    const SizedBox(width: 5),
                    Text(
                      trendLabel.toUpperCase(),
                      style: mono.channel.copyWith(color: trendColor),
                    ),
                  ],
                ),
                if (timeline.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _AdherenceSeries(timeline: timeline),
                ],
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stat(
                      context,
                      label: 'STREAK',
                      value: '${insights.currentStreakDays}',
                      unit: ' d',
                      first: true,
                    ),
                    _stat(
                      context,
                      label: 'BEST',
                      value: '${insights.longestStreakDays}',
                      unit: ' d',
                    ),
                    _stat(
                      context,
                      label: 'ADHERENCE',
                      value: '${reflection.adherencePercent}',
                      unit: '%',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: palette.outlineVariant),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        insights.supportiveMessage,
                        style: text.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One tracked stat in the footer row, separated by a hairline rule.
  Widget _stat(
    BuildContext context, {
    required String label,
    required String value,
    required String unit,
    bool first = false,
  }) {
    final palette = context.fsmPalette;
    final mono = context.fsmTelemetry;
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: first ? 0 : 14),
        decoration: first
            ? null
            : BoxDecoration(
                border: Border(
                  left: BorderSide(color: palette.outlineVariant),
                ),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: mono.channel, maxLines: 1),
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(
                text: value,
                style: mono.readout,
                children: [TextSpan(text: unit, style: mono.unit)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The daily adherence series — one bar per day in the journey's own timeline.
///
/// Height and colour both come from that day's stored `adherencePercent`, so
/// the series is never conveyed by colour alone. A day with **no doses
/// scheduled** is drawn as a flat neutral tick rather than a zero-percent bar:
/// nothing was due, so nothing was missed.
class _AdherenceSeries extends StatelessWidget {
  const _AdherenceSeries({required this.timeline});

  final List<DayJourneyCard> timeline;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final colors = context.fsmColors;

    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < timeline.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(child: _bar(timeline[i], palette, colors)),
          ],
        ],
      ),
    );
  }

  Widget _bar(
    DayJourneyCard day,
    ForeSeeMePalette palette,
    ForeSeeMeColors colors,
  ) {
    if (day.totalDoses == 0) {
      return Container(
        height: 3,
        decoration: BoxDecoration(
          color: palette.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    final percent = day.adherencePercent.clamp(0, 100);
    final color = switch (percent) {
      100 => colors.success.withValues(alpha: 0.55),
      > 0 => colors.warning.withValues(alpha: 0.50),
      _ => palette.error.withValues(alpha: 0.45),
    };
    return FractionallySizedBox(
      heightFactor: (percent / 100).clamp(0.10, 1.0),
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
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
