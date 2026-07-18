import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/animated_count_text.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// Weekly Reflection (Feature 4): an automatically generated summary of the
/// week, framed supportively even where it flags something to work on.
class WeeklyReflectionCard extends StatelessWidget {
  const WeeklyReflectionCard({super.key, required this.reflection});

  final WeeklyReflection reflection;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final delta = reflection.comparedToLastWeek;
    final deltaLabel = delta > 0
        ? '+$delta%'
        : delta < 0
        ? '$delta%'
        : 'Steady';
    final deltaColor = delta > 0
        ? context.fsmColors.success
        : delta < 0
        ? palette.error
        : palette.textSecondary;
    final deltaIcon = delta > 0
        ? Icons.trending_up_rounded
        : delta < 0
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;

    return Semantics(
      container: true,
      label:
          'This week: ${reflection.adherencePercent} percent adherence, '
          '$deltaLabel compared to last week. '
          'Longest streak ${reflection.longestStreak} days. '
          '${reflection.missedDoses} missed doses. '
          '${reflection.bestDay != null ? 'Best day ${reflection.bestDay}.' : ''} '
          '${reflection.needsAttention != null ? '${reflection.needsAttention} could use attention.' : 'Nothing needs attention this week.'}',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          padding: const EdgeInsets.all(20),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This Week', style: text.titleLarge),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _statTile(
                      context,
                      label: 'Adherence',
                      valueWidget: AnimatedCountText(
                        value: reflection.adherencePercent,
                        suffix: '%',
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _statTile(
                      context,
                      label: 'vs. Last Week',
                      valueWidget: Row(
                        children: [
                          Icon(deltaIcon, color: deltaColor, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            deltaLabel,
                            style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: deltaColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _statTile(
                      context,
                      label: 'Longest Streak',
                      valueWidget: Text(
                        '${reflection.longestStreak} days',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _statTile(
                      context,
                      label: 'Missed Doses',
                      valueWidget: Text(
                        '${reflection.missedDoses}',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: ForeSeeMeSurface.stroke(context)),
              const SizedBox(height: 12),
              _infoRow(
                context,
                icon: Icons.emoji_events_rounded,
                label: 'Best day',
                value: reflection.bestDay ?? 'Not enough data yet',
              ),
              const SizedBox(height: 10),
              _infoRow(
                context,
                icon: Icons.spa_rounded,
                label: 'Needs attention',
                value: reflection.needsAttention ?? "Nothing — great job!",
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(
    BuildContext context, {
    required String label,
    required Widget valueWidget,
  }) {
    final palette = context.fsmPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.fsmText.labelSmall?.copyWith(
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          valueWidget,
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: palette.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: text.labelSmall?.copyWith(color: palette.textTertiary),
              ),
              Text(
                value,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
