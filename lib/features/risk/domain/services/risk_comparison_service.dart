// Descriptive comparison derivations over stored risk estimates (Sprint 5,
// Prompt 9). Framework-free (no Flutter), mirroring `risk_trend_service.dart` /
// `risk_driver_service.dart`: pure, deterministic, unit-testable.
//
// IMPORTANT — honest to the stored data. Each `riskEstimates` document holds ONE
// *dominant* disease per (city, week). So these comparisons only ever describe
// what is stored; they never fabricate a per-disease risk that was not recorded:
//   • Cities   — the latest dominant estimate for each city, ranked by severity.
//   • Diseases — the diseases that have actually been the dominant risk for a
//     city over its recent history, each with its most recent level + how many
//     weeks it led. This is a descriptive breakdown, not simultaneous per-disease
//     scoring (which the pipeline does not store).

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// Severity order for ranking (Low < Medium < High).
int severityRank(RiskLevel level) => switch (level) {
  RiskLevel.low => 1,
  RiskLevel.medium => 2,
  RiskLevel.high => 3,
};

/// A bar fraction in `(0, 1]` encoding severity — for the comparison chart. The
/// bar is always accompanied by a text label + icon, never colour alone.
double severityFraction(RiskLevel level) => severityRank(level) / 3.0;

/// Latest estimate per city, ranked most-severe first (ties: higher confidence,
/// then city name for stable order). Input is the latest-per-city list from the
/// repository; cities without an estimate are simply absent.
List<RiskEstimateModel> rankCitiesBySeverity(List<RiskEstimateModel> latest) {
  final ranked = [...latest];
  ranked.sort((a, b) {
    final bySeverity = severityRank(b.riskLevel).compareTo(severityRank(a.riskLevel));
    if (bySeverity != 0) return bySeverity;
    final byConfidence = b.confidence.compareTo(a.confidence);
    if (byConfidence != 0) return byConfidence;
    return a.city.compareTo(b.city);
  });
  return ranked;
}

/// A disease's descriptive summary within one city's recent history.
class DiseaseRiskSummary {
  final String disease;

  /// The most recent recorded level for this disease in the window.
  final RiskLevel latestLevel;

  /// True when the latest estimate for this disease was low-confidence.
  final bool latestLowConfidence;

  /// When that most recent estimate was generated.
  final DateTime latestAt;

  /// How many weeks in the window this disease was the dominant risk.
  final int weeksObserved;

  const DiseaseRiskSummary({
    required this.disease,
    required this.latestLevel,
    required this.latestLowConfidence,
    required this.latestAt,
    required this.weeksObserved,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiseaseRiskSummary &&
          other.disease == disease &&
          other.latestLevel == latestLevel &&
          other.latestLowConfidence == latestLowConfidence &&
          other.latestAt == latestAt &&
          other.weeksObserved == weeksObserved;

  @override
  int get hashCode =>
      Object.hash(disease, latestLevel, latestLowConfidence, latestAt, weeksObserved);
}

/// Summarise the diseases seen in a city's recent [history] (newest-first or any
/// order), one row per distinct disease, ranked by the severity of its most
/// recent level then recency. Returns an empty list for empty history.
List<DiseaseRiskSummary> summarizeDiseasesForCity(
  List<RiskEstimateModel> history,
) {
  final byDisease = <String, List<RiskEstimateModel>>{};
  for (final estimate in history) {
    byDisease.putIfAbsent(estimate.disease, () => []).add(estimate);
  }

  final summaries = <DiseaseRiskSummary>[];
  byDisease.forEach((disease, entries) {
    entries.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    final latest = entries.first;
    summaries.add(
      DiseaseRiskSummary(
        disease: disease,
        latestLevel: latest.riskLevel,
        latestLowConfidence: latest.lowConfidence,
        latestAt: latest.generatedAt,
        weeksObserved: entries.length,
      ),
    );
  });

  summaries.sort((a, b) {
    final bySeverity = severityRank(b.latestLevel).compareTo(severityRank(a.latestLevel));
    if (bySeverity != 0) return bySeverity;
    return b.latestAt.compareTo(a.latestAt);
  });
  return summaries;
}
