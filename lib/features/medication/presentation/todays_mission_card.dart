import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// Today's Mission (Sprint UX-M2.3): the single next actionable step,
/// answering "what should I do today?" — sits directly below Journey
/// Progress. Updates automatically from pending doses, the current time,
/// medication schedules, and the current streak (all computed once in
/// `AdherenceJourneyService`; this widget only renders).
class TodaysMissionCard extends StatelessWidget {
  const TodaysMissionCard({super.key, required this.mission});

  final TodaysMission mission;

  String _formatTime(String? raw) {
    if (raw == null) return '';
    final parts = raw.split(':');
    if (parts.length != 2) return raw;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final readHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$readHour:$minute $suffix';
  }

  (String, Color) _visual(BuildContext context) {
    final palette = context.fsmPalette;
    return switch (mission.state) {
      MissionState.pending => ('🎯', palette.primary),
      MissionState.allComplete => ('🎉', context.fsmColors.success),
      MissionState.dayOver => ('🌙', palette.secondary),
      MissionState.noMedications => ('☀️', palette.secondary),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final (emoji, tint) = _visual(context);
    final deadline = _formatTime(mission.rawDeadlineTime);

    return Semantics(
      container: true,
      label: "Today's mission: ${mission.title}. ${mission.message}",
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          padding: const EdgeInsets.all(18),
          decoration: ForeSeeMeSurface.card(
            context,
            radius: ForeSeeMeRadius.md,
            borderColor: tint.withValues(alpha: 0.30),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            child: Row(
              key: ValueKey(mission.state),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withValues(alpha: 0.14),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Mission",
                        style: text.labelSmall?.copyWith(
                          color: palette.textTertiary,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mission.title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (mission.state == MissionState.pending &&
                          deadline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Before $deadline',
                          style: text.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        mission.message,
                        style: text.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
