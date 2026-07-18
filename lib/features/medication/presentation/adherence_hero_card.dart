import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/animated_count_text.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';

/// Storytelling hero (Feature 1): a supportive headline + message driven by
/// [story], a donut of the real weekly rate, and streak chips. All colour is
/// resolved from the ForeSeeMe design system for the ambient brightness.
class AdherenceHeroCard extends StatelessWidget {
  const AdherenceHeroCard({super.key, required this.stats, required this.story});

  final List<AdherenceStatsModel> stats;
  final HeroStory story;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    final overall = stats.firstWhere(
      (stat) => stat.medicationId == 'overall',
      orElse: () => stats.first,
    );
    final meds = stats.where((stat) => stat.medicationId != 'overall');
    final streak = meds.fold<int>(0, (max, stat) {
      return stat.currentStreak > max ? stat.currentStreak : max;
    });
    final best = meds.fold<int>(0, (max, stat) {
      return stat.longestStreak > max ? stat.longestStreak : max;
    });
    final rate = overall.weeklyRate.clamp(0.0, 1.0);
    final percent = (rate * 100).round();

    return Semantics(
      container: true,
      label: '${story.emoji} ${story.headline} ${story.message} '
          "This week's adherence: $percent percent. "
          'Current streak $streak days, best $best days.',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          padding: const EdgeInsets.all(22),
          decoration: ForeSeeMeSurface.card(
            context,
            radius: ForeSeeMeRadius.md,
            borderColor: palette.primary.withValues(alpha: 0.42),
            shadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: 0.20),
                blurRadius: 38,
                spreadRadius: -18,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: Column(
                  key: ValueKey(story.headline),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(story.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            story.headline,
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.message,
                      style: text.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _statChip(context, '🔥 $streak Day Streak'),
                  const Spacer(),
                  _statChip(context, '📅 Best: $best Days'),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            palette.primary.withValues(alpha: 0.34),
                            palette.primary.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                    PieChart(
                      PieChartData(
                        startDegreeOffset: -90,
                        sectionsSpace: 3,
                        centerSpaceRadius: 58,
                        centerSpaceColor: Colors.transparent,
                        sections: [
                          PieChartSectionData(
                            value: rate == 0 ? .001 : rate,
                            radius: 20,
                            showTitle: false,
                            gradient: LinearGradient(
                              colors: [palette.primary, palette.secondary],
                            ),
                            cornerRadius: 18,
                          ),
                          PieChartSectionData(
                            value: 1 - rate,
                            radius: 20,
                            showTitle: false,
                            color: palette.surfaceContainerHighest,
                          ),
                        ],
                      ),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedCountText(
                          value: percent,
                          suffix: '%',
                          style: text.displayLarge?.copyWith(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          "This Week's Adherence",
                          style: text.bodyMedium?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
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

  Widget _statChip(BuildContext context, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: context.fsmPalette.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
    ),
    child: Text(
      label,
      style: context.fsmText.labelMedium?.copyWith(
        color: context.fsmPalette.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
