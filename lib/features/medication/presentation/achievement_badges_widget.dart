import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_helpers.dart';

/// Achievement System (Feature 3): badges unlock automatically from
/// deterministic adherence rules (see `AdherenceJourneyService`). Locked
/// badges stay visible, greyed out — the whole set is always shown so users
/// can see what's still ahead of them.
class AchievementBadgesWidget extends StatelessWidget {
  const AchievementBadgesWidget({super.key, required this.achievements});

  final List<Achievement> achievements;

  @override
  Widget build(BuildContext context) {
    final text = context.fsmText;
    final palette = context.fsmPalette;
    final unlockedCount = achievements.where((a) => a.unlocked).length;

    return Semantics(
      container: true,
      label:
          'Achievements: $unlockedCount of ${achievements.length} unlocked.',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        padding: const EdgeInsets.all(18),
        decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Achievements', style: text.titleLarge),
                const Spacer(),
                Text(
                  '$unlockedCount/${achievements.length}',
                  style: text.labelLarge?.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                for (var i = 0; i < achievements.length; i++)
                  StaggeredReveal(
                    delay: Duration(milliseconds: i * 70),
                    child: _AchievementBadge(achievement: achievements[i]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final unlocked = achievement.unlocked;

    return Semantics(
      label:
          '${achievement.title}: ${achievement.description}. '
          '${unlocked ? 'Unlocked' : 'Locked'}.',
      child: ExcludeSemantics(
        child: SizedBox(
          // 92dp keeps the tap/label target comfortably above the 48dp
          // minimum while fitting 3 per row on a typical phone width.
          width: 92,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unlocked
                      ? palette.primary.withValues(alpha: 0.14)
                      : palette.surfaceContainerHighest,
                  border: Border.all(
                    color: unlocked
                        ? palette.primary.withValues(alpha: 0.4)
                        : palette.outlineVariant,
                    width: ForeSeeMeBorderWidth.thin,
                  ),
                ),
                child: Opacity(
                  opacity: unlocked ? 1.0 : 0.35,
                  child: Text(
                    achievement.emoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                achievement.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: unlocked ? palette.textPrimary : palette.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
