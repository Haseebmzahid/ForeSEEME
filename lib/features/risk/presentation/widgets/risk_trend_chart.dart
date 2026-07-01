import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// Premium "Risk index" trend line for the Risk Details screen.
///
/// Plots the **real** historical estimates only (level ordinal Low=0 / Medium=1 /
/// High=2 per point) — it never fabricates points; the curve is purely visual
/// smoothing between real values. Features: smooth curve, gradient fill, rounded
/// caps, a subtle grid, relative day/week x-labels, a touch tooltip, and an
/// animated draw on open that respects the reduced-motion setting. Dark-theme
/// native (Design System v2).
class RiskTrendChart extends StatelessWidget {
  /// Trailing history (any order; sorted ascending internally). Must have ≥2
  /// points — the caller shows an empty state otherwise.
  final List<RiskEstimateModel> history;

  /// Line/fill colour — the latest estimate's risk colour.
  final Color color;

  const RiskTrendChart({super.key, required this.history, required this.color});

  static int _score(RiskLevel l) => switch (l) {
    RiskLevel.low => 0,
    RiskLevel.medium => 1,
    RiskLevel.high => 2,
  };

  static String _levelName(int score) => switch (score) {
    0 => 'Low',
    1 => 'Medium',
    _ => 'High',
  };

  @override
  Widget build(BuildContext context) {
    final ordered = [...history]
      ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    final labels = _relativeLabels(ordered);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final realSpots = [
      for (var i = 0; i < ordered.length; i++)
        FlSpot(i.toDouble(), _score(ordered[i].riskLevel).toDouble()),
    ];

    return Semantics(
      label:
          'Risk index trend over the last ${ordered.length} estimates, '
          'ending ${_levelName(_score(ordered.last.riskLevel))}.',
      child: SizedBox(
        height: 180,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
          duration: Duration(milliseconds: reduceMotion ? 0 : 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final spots = [for (final s in realSpots) FlSpot(s.x, s.y * t)];
            return LineChart(
              _data(spots, ordered, labels),
              duration:
                  Duration.zero, // the tween drives the draw, not fl_chart
            );
          },
        ),
      ),
    );
  }

  LineChartData _data(
    List<FlSpot> spots,
    List<RiskEstimateModel> ordered,
    List<String> labels,
  ) {
    final lastX = (ordered.length - 1).toDouble();
    return LineChartData(
      minX: 0,
      maxX: lastX,
      minY: -0.25,
      maxY: 2.25,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppColorsV2.stroke.withValues(alpha: 0.6),
          strokeWidth: 1,
          dashArray: const [4, 6],
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.round();
              if (i < 0 || i >= labels.length || labels[i].isEmpty) {
                return const SizedBox.shrink();
              }
              final isNow = i == labels.length - 1;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[i],
                  style: AppTextStylesV2.caption.copyWith(
                    fontSize: 10,
                    color: isNow ? color : AppColorsV2.textFaint,
                    fontWeight: isNow ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        getTouchLineStart: (_, _) => 0,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColorsV2.shellRaised,
          tooltipBorderRadius: BorderRadius.circular(10),
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          getTooltipItems: (touched) => [
            for (final spot in touched)
              LineTooltipItem(
                '${_levelName(_score(ordered[spot.x.round()].riskLevel))} risk\n',
                AppTextStylesV2.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
                children: [
                  TextSpan(
                    text: _labelFor(ordered, spot.x.round()),
                    style: AppTextStylesV2.caption.copyWith(
                      color: AppColorsV2.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.32,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => spot.x == (ordered.length - 1),
            getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
              radius: 4,
              color: color,
              strokeWidth: 2,
              strokeColor: AppColorsV2.shell,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.02),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _labelFor(List<RiskEstimateModel> ordered, int i) {
    if (i == ordered.length - 1) return 'Now';
    final days = ordered.last.generatedAt
        .difference(ordered[i].generatedAt)
        .inDays;
    return _useWeeks(ordered)
        ? '${(days / 7).round()} weeks ago'
        : '$days days ago';
  }

  /// Compact axis labels (a subset to avoid clutter): first, last, and a couple
  /// in between depending on point count.
  List<String> _relativeLabels(List<RiskEstimateModel> ordered) {
    final n = ordered.length;
    final weeks = _useWeeks(ordered);
    final step = n <= 6 ? 1 : (n / 5).ceil();
    return [
      for (var i = 0; i < n; i++)
        if (i == n - 1)
          'Now'
        else if (i % step == 0)
          _short(
            ordered.last.generatedAt.difference(ordered[i].generatedAt).inDays,
            weeks,
          )
        else
          '',
    ];
  }

  bool _useWeeks(List<RiskEstimateModel> ordered) {
    final span = ordered.last.generatedAt
        .difference(ordered.first.generatedAt)
        .inDays;
    return span >= 14;
  }

  String _short(int days, bool weeks) =>
      weeks ? '${(days / 7).round()}w' : '${days}d';
}
