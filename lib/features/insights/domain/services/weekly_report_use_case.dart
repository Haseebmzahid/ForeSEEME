// Weekly Health Report composition (Sprint 5, Prompt 8).
//
// Framework-free (no Flutter), mirroring the other domain composers. A pure,
// deterministic function that ties EXISTING signals — the week's environmental
// risk, the risk trend, the user's adherence insights, and a CITED recommendation
// — into one descriptive, non-diagnostic digest. It generates no medical text
// (the advisory is a cited lookup, carried verbatim) and describes the
// *environment* and the *estimate*, never the person's diagnosis.

import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/weekly_report.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';

/// Compose the weekly report from already-resolved signals.
///
/// All inputs come from existing providers; nothing is fetched or recomputed
/// here. Deterministic: the same inputs always yield the same report.
WeeklyReport composeWeeklyReport({
  required DateTime weekOf,
  required RiskEstimateModel? risk,
  required TrendDirection trend,
  required AdherenceInsights adherence,
  required HealthRecommendation? recommendation,
}) {
  return WeeklyReport(
    weekOf: weekOf,
    city: risk?.city,
    risk: risk,
    adherence: adherence,
    recommendation: recommendation,
    riskSection: _riskSection(risk, trend),
    adherenceSection: _adherenceSection(adherence),
    recommendationSection: _recommendationSection(recommendation),
  );
}

// ── Risk section (descriptive, non-diagnostic) ───────────────────────────────

WeeklyReportSection _riskSection(RiskEstimateModel? risk, TrendDirection trend) {
  if (risk == null) {
    return const WeeklyReportSection(
      title: 'This week’s environment',
      body:
          'We don’t have an environmental risk estimate for your city this week '
          'yet. New estimates arrive weekly — check back soon.',
    );
  }
  final pct = (risk.confidence * 100).round();
  final level = risk.riskLevel.toJson();
  final trendNote = _trendNote(trend);
  return WeeklyReportSection(
    title: 'This week’s environment',
    body:
        '${risk.city}’s environment shows $level risk for ${risk.disease} this '
        'week (about $pct% confidence).$trendNote',
  );
}

String _trendNote(TrendDirection trend) => switch (trend) {
  TrendDirection.rising => ' The recent trend is rising.',
  TrendDirection.falling => ' The recent trend is improving.',
  TrendDirection.stable => ' The recent trend is stable.',
  TrendDirection.insufficient => '',
};

// ── Adherence section (reuses the supportive copy) ───────────────────────────

WeeklyReportSection _adherenceSection(AdherenceInsights adherence) {
  if (!adherence.hasData) {
    return const WeeklyReportSection(
      title: 'Your routine',
      body:
          'Log a few doses and a gentle, supportive summary of your routine will '
          'appear here each week.',
    );
  }
  return WeeklyReportSection(
    title: 'Your routine',
    body: '${adherence.headline}. ${adherence.supportiveMessage}',
  );
}

// ── Cited recommendation section (looked up, never generated) ────────────────

WeeklyReportSection? _recommendationSection(HealthRecommendation? recommendation) {
  if (recommendation == null) return null;
  return WeeklyReportSection(
    title: 'What may help',
    body: recommendation.text,
  );
}
