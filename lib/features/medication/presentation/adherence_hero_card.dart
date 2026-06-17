import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';

class AdherenceHeroCard extends StatelessWidget {
  const AdherenceHeroCard({super.key, required this.stats});

  final List<AdherenceStatsModel> stats;

  @override
  Widget build(BuildContext context) {
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.adherenceSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.adherencePrimary.withValues(alpha: .42),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.adherencePrimary.withValues(alpha: .20),
            blurRadius: 38,
            spreadRadius: -18,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statChip('🔥 $streak Day Streak'),
              const Spacer(),
              _statChip('📅 Best: $best Days'),
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
                        AppColors.adherencePrimary.withValues(alpha: .34),
                        AppColors.adherencePrimary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                PieChart(
                  PieChartData(
                    startDegreeOffset: -90,
                    sectionsSpace: 3,
                    centerSpaceRadius: 58,
                    centerSpaceColor: AppColors.adherenceSurface,
                    sections: [
                      PieChartSectionData(
                        value: rate == 0 ? .001 : rate,
                        radius: 20,
                        showTitle: false,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.adherencePrimary,
                            AppColors.adherenceCyan,
                          ],
                        ),
                        cornerRadius: 18,
                      ),
                      PieChartSectionData(
                        value: 1 - rate,
                        radius: 20,
                        showTitle: false,
                        color: AppColors.adherenceOutline,
                      ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$percent%',
                      style: GoogleFonts.sora(
                        color: AppColors.adherenceTextPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      "This Week's Adherence",
                      style: GoogleFonts.dmSans(
                        color: AppColors.adherenceTextMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _statChip(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
    color: AppColors.adherenceSurfaceHighlight.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(999),
  ),
  child: Text(
    text,
    style: GoogleFonts.dmSans(
      color: AppColors.adherenceTextPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  ),
);
