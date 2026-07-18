import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/widgets/day_journey_detail_sheet.dart';

/// Weekly Journey Timeline (Sprint UX-M2.3): seven interactive day cards —
/// one chapter per day — replacing the old "7-Day Overview" bar chart.
/// Answers "what happened this week?" as a story, not a statistic.
class WeeklyJourneyTimeline extends StatelessWidget {
  const WeeklyJourneyTimeline({super.key, required this.days});

  final List<DayJourneyCard> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final text = context.fsmText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text("This Week's Journey", style: text.titleLarge),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _DayJourneyTile(day: days[index]),
          ),
        ),
      ],
    );
  }
}

class _DayJourneyTile extends StatelessWidget {
  const _DayJourneyTile({required this.day});

  final DayJourneyCard day;

  void _openDetail(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DayJourneyDetailSheet(day: day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;

    return Semantics(
      button: true,
      label:
          '${day.weekdayLabel}${day.isToday ? ', today' : ''}, ${day.status.label}, '
          '${day.completedDoses} of ${day.totalDoses} completed',
      child: PressableScale(
        onTap: () => _openDetail(context),
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: AppMotion.curve,
            width: 132,
            padding: const EdgeInsets.all(14),
            decoration: ForeSeeMeSurface.card(
              context,
              radius: ForeSeeMeRadius.md,
              borderColor: day.isToday
                  ? palette.primary.withValues(alpha: 0.5)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        day.weekdayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (day.isToday)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(
                            ForeSeeMeRadius.full,
                          ),
                        ),
                        child: Text(
                          'Now',
                          style: text.labelSmall?.copyWith(
                            color: palette.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: AppMotion.curve,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.85 + (0.15 * value),
                      child: child,
                    ),
                  ),
                  child: Text(
                    day.status.emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  day.status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _doseRow(context, 'Morning', day.morning),
                const SizedBox(height: 4),
                _doseRow(context, 'Evening', day.evening),
                const Spacer(),
                Text(
                  '${day.completedDoses}/${day.totalDoses} completed',
                  style: text.labelSmall?.copyWith(
                    color: palette.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _doseRow(BuildContext context, String label, DoseCompletionState state) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final (icon, color) = switch (state) {
      DoseCompletionState.taken => (
        Icons.check_circle_rounded,
        context.fsmColors.success,
      ),
      DoseCompletionState.missed => (Icons.cancel_rounded, palette.error),
      DoseCompletionState.pending => (
        Icons.more_horiz_rounded,
        palette.textTertiary,
      ),
      DoseCompletionState.none => (
        Icons.remove_rounded,
        palette.textTertiary,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: text.labelSmall?.copyWith(
            fontSize: 10,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}
