import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';

/// The Weekly Journey Timeline's detail sheet: a single day's story —
/// Morning/Evening medication outcomes, adherence %, completed/missed
/// doses, and a supportive message. Mirrors `MedicationDetailSheet`'s
/// premium Material 3 sheet styling for visual consistency.
class DayJourneyDetailSheet extends StatelessWidget {
  const DayJourneyDetailSheet({super.key, required this.day});

  final DayJourneyCard day;

  String _doseLabel(DoseCompletionState state) => switch (state) {
    DoseCompletionState.taken => 'Taken',
    DoseCompletionState.missed => 'Missed',
    DoseCompletionState.pending => 'Pending',
    DoseCompletionState.none => 'Not scheduled',
  };

  Color _statusTint(BuildContext context) => switch (day.status) {
    DayJourneyStatus.perfectDay => context.fsmColors.success,
    DayJourneyStatus.greatProgress => context.fsmColors.success,
    DayJourneyStatus.buildingHabit => context.fsmPalette.primary,
    DayJourneyStatus.today => context.fsmPalette.secondary,
    DayJourneyStatus.needsAttention => context.fsmColors.warning,
    DayJourneyStatus.missed => context.fsmPalette.error,
  };

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            value,
            style: text.bodyMedium?.copyWith(
              color: valueColor ?? palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final tint = _statusTint(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ForeSeeMeSurface.stroke(context)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: palette.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.full),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tint.withValues(alpha: 0.14),
                    ),
                    child: Text(
                      day.status.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.isToday ? '${day.weekdayLabel} (Today)' : day.weekdayLabel,
                          style: text.titleLarge,
                        ),
                        Text(
                          day.status.label,
                          style: text.bodyMedium?.copyWith(
                            color: tint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: ForeSeeMeSurface.stroke(context)),
              _detailRow(
                context,
                icon: Icons.wb_sunny_rounded,
                label: 'Morning Medication',
                value: _doseLabel(day.morning),
                valueColor: day.morning == DoseCompletionState.missed
                    ? palette.error
                    : null,
              ),
              _detailRow(
                context,
                icon: Icons.nightlight_round,
                label: 'Evening Medication',
                value: _doseLabel(day.evening),
                valueColor: day.evening == DoseCompletionState.missed
                    ? palette.error
                    : null,
              ),
              Divider(color: ForeSeeMeSurface.stroke(context)),
              _detailRow(
                context,
                icon: Icons.donut_large_rounded,
                label: 'Adherence',
                value: '${day.adherencePercent}%',
              ),
              _detailRow(
                context,
                icon: Icons.check_circle_outline_rounded,
                label: 'Completed Doses',
                value: '${day.completedDoses}',
              ),
              _detailRow(
                context,
                icon: Icons.cancel_outlined,
                label: 'Missed Doses',
                value: '${day.missedDoses}',
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
                  border: Border.all(
                    color: tint.withValues(alpha: 0.20),
                    width: ForeSeeMeBorderWidth.hairline,
                  ),
                ),
                child: Text(
                  day.supportingMessage,
                  style: text.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PressableScale(
                onTap: () => Navigator.of(context).pop(),
                child: Semantics(
                  button: true,
                  label: 'Close',
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: palette.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
                      border: Border.all(
                        color: palette.outlineVariant,
                        width: ForeSeeMeBorderWidth.hairline,
                      ),
                    ),
                    child: Text(
                      'Got it',
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
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
