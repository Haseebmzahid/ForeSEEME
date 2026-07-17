import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';

/// Per-medication adherence summary: the last 7 days as status dots plus a
/// weekly-rate progress bar. Colour comes from the ForeSeeMe design system.
class MedicationAdherenceCard extends StatelessWidget {
  const MedicationAdherenceCard({super.key, required this.stat});

  final AdherenceStatsModel stat;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final days = stat.last30DaysLog.length <= 7
        ? stat.last30DaysLog
        : stat.last30DaysLog.sublist(stat.last30DaysLog.length - 7);
    final percent = (stat.weeklyRate.clamp(0.0, 1.0) * 100).round();

    return Semantics(
      container: true,
      label: '${stat.medicationName}, ${stat.dosage}: $percent percent adherence',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          padding: const EdgeInsets.all(18),
          decoration: ForeSeeMeSurface.card(
            context,
            radius: ForeSeeMeRadius.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stat.medicationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.secondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                    ),
                    child: Text(
                      stat.dosage,
                      style: text.labelSmall?.copyWith(
                        color: palette.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final day in days) ...[
                    _StatusDot(status: day.status),
                    const SizedBox(width: 9),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                child: LinearProgressIndicator(
                  value: stat.weeklyRate.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: palette.surfaceContainerHighest,
                  color: palette.primary,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$percent% adherence',
                  style: text.labelMedium?.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final DailyAdherenceStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final fill = switch (status) {
      DailyAdherenceStatus.taken => context.fsmColors.success,
      DailyAdherenceStatus.skipped => palette.error,
      _ => palette.surfaceContainerHighest,
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: status == DailyAdherenceStatus.pending
            ? Border.all(color: palette.outlineVariant)
            : null,
      ),
    );
  }
}
