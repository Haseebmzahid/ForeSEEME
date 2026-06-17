import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';

class MedicationAdherenceCard extends StatelessWidget {
  const MedicationAdherenceCard({super.key, required this.stat});

  final AdherenceStatsModel stat;

  @override
  Widget build(BuildContext context) {
    final days = stat.last30DaysLog.length <= 7
        ? stat.last30DaysLog
        : stat.last30DaysLog.sublist(stat.last30DaysLog.length - 7);
    final percent = (stat.weeklyRate.clamp(0.0, 1.0) * 100).round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.adherenceSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.adherenceOutline),
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
                  style: GoogleFonts.sora(
                    color: AppColors.adherenceTextPrimary,
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
                  color: AppColors.adherencePrimary.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stat.dosage,
                  style: GoogleFonts.dmSans(
                    color: AppColors.adherenceCyan,
                    fontSize: 11,
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
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: stat.weeklyRate.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.adherenceOutline,
              color: AppColors.adherencePrimary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$percent% adherence',
              style: GoogleFonts.dmSans(
                color: AppColors.adherenceTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final DailyAdherenceStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _fill,
        border: _border,
      ),
    );
  }

  Color get _fill {
    return switch (status) {
      DailyAdherenceStatus.taken => AppColors.adherencePrimary,
      DailyAdherenceStatus.skipped => AppColors.adherenceCoral,
      _ => AppColors.adherenceSurfaceHighlight,
    };
  }

  BoxBorder? get _border {
    return status == DailyAdherenceStatus.pending
        ? Border.all(color: AppColors.adherenceOutline)
        : null;
  }
}
