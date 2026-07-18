import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// Medication Journey Levels (Feature 2): a 5-tier progression
/// (🌱 Beginner → 🏆 Asthma Champion) replacing a bare percentage with a
/// sense of advancement.
class MedicationJourneyLevelCard extends StatelessWidget {
  const MedicationJourneyLevelCard({
    super.key,
    required this.level,
    required this.levelProgress,
    required this.percentToNextLevel,
  });

  final MedicationLevel level;
  final double levelProgress;
  final int percentToNextLevel;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final next = level.next;

    return Semantics(
      container: true,
      label: next == null
          ? 'Medication journey level: ${level.label}, the highest level.'
          : 'Medication journey level: ${level.label}. '
                '$percentToNextLevel percent to ${next.label}.',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          padding: const EdgeInsets.all(20),
          decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(level.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          level.label,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          next == null
                              ? "You've reached the top level"
                              : '$percentToNextLevel% to ${next.label}',
                          style: text.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AnimatedLevelBar(progress: levelProgress),
              const SizedBox(height: 16),
              _LevelStepper(currentLevel: level),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLevelBar extends StatelessWidget {
  const _AnimatedLevelBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final reduce = AppMotion.reduceMotion(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
        curve: AppMotion.curve,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: 10,
          backgroundColor: palette.surfaceContainerHighest,
          color: palette.primary,
        ),
      ),
    );
  }
}

class _LevelStepper extends StatelessWidget {
  const _LevelStepper({required this.currentLevel});

  final MedicationLevel currentLevel;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final currentIndex = MedicationLevel.values.indexOf(currentLevel);

    return Row(
      children: [
        for (final level in MedicationLevel.values) ...[
          _LevelDot(
            level: level,
            reached: MedicationLevel.values.indexOf(level) <= currentIndex,
          ),
          if (level != MedicationLevel.values.last)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color:
                    MedicationLevel.values.indexOf(level) < currentIndex
                    ? palette.primary
                    : palette.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _LevelDot extends StatelessWidget {
  const _LevelDot({required this.level, required this.reached});

  final MedicationLevel level;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached
            ? palette.primary.withValues(alpha: 0.16)
            : palette.surfaceContainerHighest,
        border: Border.all(
          color: reached ? palette.primary : palette.outlineVariant,
          width: ForeSeeMeBorderWidth.thin,
        ),
      ),
      child: Text(
        level.emoji,
        style: TextStyle(
          fontSize: 14,
          color: reached ? null : palette.textTertiary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
