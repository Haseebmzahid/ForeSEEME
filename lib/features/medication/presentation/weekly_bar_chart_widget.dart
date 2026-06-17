import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_stats_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_data.dart';

class WeeklyBarChartWidget extends StatelessWidget {
  const WeeklyBarChartWidget({super.key, required this.stats});

  final List<AdherenceStatsModel> stats;

  @override
  Widget build(BuildContext context) {
    final days = last7Days();
    final counts = weeklyCounts(stats);
    final maxCount = counts.fold<int>(
      1,
      (max, day) => max < day.total ? day.total : max,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.adherenceSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.adherencePrimary, width: 4),
              ),
            ),
            child: Text(
              '7-Day Overview',
              style: GoogleFonts.sora(
                color: AppColors.adherenceTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: max(3, maxCount + 1).toDouble(),
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.adherenceOutline.withValues(alpha: .45),
                    strokeWidth: .8,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value % 1 != 0) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            value.toInt().toString(),
                            style: GoogleFonts.dmSans(
                              color: AppColors.adherenceTextMuted,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= days.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            weekdayLabel(days[index]),
                            style: GoogleFonts.dmSans(
                              color: AppColors.adherenceTextMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 5,
                      barRods: [
                        _rod(counts[i].taken.toDouble(), true),
                        _rod(counts[i].skipped.toDouble(), false),
                      ],
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  BarChartRodData _rod(double value, bool taken) {
    return BarChartRodData(
      toY: value,
      width: 9,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      color: taken ? null : AppColors.adherenceCoral,
      gradient: taken
          ? LinearGradient(
              colors: [AppColors.adherencePrimary, AppColors.adherenceCyan],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            )
          : null,
    );
  }
}
