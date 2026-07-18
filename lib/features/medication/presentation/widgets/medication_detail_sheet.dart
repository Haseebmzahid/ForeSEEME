import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/adherence_journey_service.dart';

/// Detail bottom sheet for a single medication: name, dosage, frequency,
/// reminder times, start date and status, a mini adherence dashboard
/// (Feature 9 — current adherence, next reminder, current streak), plus
/// Edit / Archive / Cancel actions. Pure widget — [onEdit] and [onArchive]
/// are injected so it is testable without a repository or router. [stat] is
/// optional: the dashboard section is simply omitted while adherence stats
/// are still loading (never blocks opening the sheet).
class MedicationDetailSheet extends StatelessWidget {
  final MedicationModel medication;
  final AdherenceStatsModel? stat;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const MedicationDetailSheet({
    super.key,
    required this.medication,
    this.stat,
    required this.onEdit,
    required this.onArchive,
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatTime(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) return timeString;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final readHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$readHour:$minute $suffix';
  }

  String _formatStartDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.labelSmall?.copyWith(color: palette.textTertiary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: text.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDashboard(BuildContext context, AdherenceStatsModel stat) {
    final percent = (stat.weeklyRate.clamp(0.0, 1.0) * 100).round();
    final nextReminder = AdherenceJourneyService.nextReminderFor(
      medication,
      DateTime.now(),
    );

    return Row(
      children: [
        _miniStatCard(
          context,
          icon: Icons.favorite_rounded,
          label: 'Current Adherence',
          value: '$percent%',
        ),
        const SizedBox(width: 10),
        _miniStatCard(
          context,
          icon: Icons.notifications_active_rounded,
          label: 'Next Reminder',
          value: nextReminder == null ? '—' : _formatTime(nextReminder.rawTime),
          subValue: nextReminder?.label,
        ),
        const SizedBox(width: 10),
        _miniStatCard(
          context,
          icon: Icons.local_fire_department_rounded,
          label: 'Current Streak',
          value: '${stat.currentStreak} Days',
        ),
      ],
    );
  }

  Widget _miniStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
  }) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: palette.surfaceContainerLow,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          border: Border.all(
            color: palette.outlineVariant,
            width: ForeSeeMeBorderWidth.hairline,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: palette.secondary),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subValue != null)
              Text(
                subValue,
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(color: palette.textSecondary),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(color: palette.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color tint,
    required VoidCallback onTap,
  }) {
    final text = context.fsmText;
    return PressableScale(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
            border: Border.all(
              color: tint.withValues(alpha: 0.20),
              width: ForeSeeMeBorderWidth.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final isActive = medication.isActive;
    final statusTint = isActive ? context.fsmColors.success : palette.error;
    final reminderText = medication.reminderTimes.isEmpty
        ? 'No reminders set'
        : medication.reminderTimes.map(_formatTime).join(', ');

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                      gradient: LinearGradient(
                        colors: [palette.primary, palette.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      color: palette.onPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(medication.name, style: text.titleLarge),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusTint.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActive ? 'ACTIVE' : 'ARCHIVED',
                            style: text.labelSmall?.copyWith(
                              color: statusTint,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
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
                icon: Icons.medication_rounded,
                label: 'Dosage',
                value: medication.dosage,
              ),
              _detailRow(
                context,
                icon: Icons.repeat_rounded,
                label: 'Frequency',
                value: medication.frequency.label,
              ),
              _detailRow(
                context,
                icon: Icons.access_time_rounded,
                label: 'Reminder Times',
                value: reminderText,
              ),
              _detailRow(
                context,
                icon: Icons.event_rounded,
                label: 'Start Date',
                value: _formatStartDate(medication.createdAt),
              ),
              if (stat != null) ...[
                const SizedBox(height: 8),
                Divider(color: ForeSeeMeSurface.stroke(context)),
                const SizedBox(height: 4),
                _buildMiniDashboard(context, stat!),
              ],
              const SizedBox(height: 16),
              _actionRow(
                context,
                icon: Icons.edit_rounded,
                label: 'Edit Medication',
                tint: palette.primary,
                onTap: onEdit,
              ),
              const SizedBox(height: 10),
              _actionRow(
                context,
                icon: Icons.archive_outlined,
                label: 'Archive Medication',
                tint: palette.error,
                onTap: onArchive,
              ),
              const SizedBox(height: 10),
              _actionRow(
                context,
                icon: Icons.close_rounded,
                label: 'Cancel',
                tint: palette.textSecondary,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
