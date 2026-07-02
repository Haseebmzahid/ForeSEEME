// Deterministic recommendation prioritization (Sprint 5, Prompt 10).
//
// Framework-free, pure. Ranks the CITED recommendations (never generated —
// Rule 11) for the current risk by relevance × severity, so the most relevant
// guidance is surfaced first:
//   • relevance — an advisory whose (category, driver) matches the user's chronic
//     condition and the current disease's driver is more relevant than the
//     general default;
//   • severity  — higher current risk lifts every score, and (with a matched
//     advisory present) always keeps the specific advice above the default.
//
// It reuses the frozen mapper maps (condition→category, disease→driver/
// categories, category priority) — it does NOT redesign targeting. Selection is
// via the total [RecommendationRepository.lookup], so every result is sourced.

import 'package:fyp_foreseeme/features/insights/domain/repositories/recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_mapper.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// A cited recommendation with its deterministic priority.
class PrioritizedRecommendation {
  final HealthRecommendation recommendation;

  /// 1-based rank (1 = most relevant).
  final int rank;

  /// True when it matches the user's condition category + the current driver
  /// (as opposed to the general cited default).
  final bool matchesCondition;

  /// The deterministic relevance score it was ranked by.
  final double relevance;

  const PrioritizedRecommendation({
    required this.recommendation,
    required this.rank,
    required this.matchesCondition,
    required this.relevance,
  });
}

int _severityWeight(RiskLevel level) => switch (level) {
  RiskLevel.low => 1,
  RiskLevel.medium => 2,
  RiskLevel.high => 3,
};

class _Candidate {
  final HealthRecommendation recommendation;
  final bool matches;
  final int categoryIndex; // lower = higher priority
  const _Candidate(this.recommendation, this.matches, this.categoryIndex);
}

/// Rank the cited recommendations for the current risk, most relevant first.
///
/// Deterministic for a fixed `(riskLevel, disease, conditions)`: candidates are
/// generated in [kCategoryPriority] order (matched advisories) plus the cited
/// default, de-duplicated by id, scored, then sorted by relevance desc with a
/// category-priority (then id) tie-break. Always returns at least the default.
List<PrioritizedRecommendation> prioritizeRecommendations({
  required RiskLevel riskLevel,
  required String disease,
  required List<String> conditions,
  required RecommendationRepository repository,
}) {
  final driver = kDiseaseDriver[disease] ?? kDefaultDriver;
  final matched = userCategories(
    conditions,
  ).intersection(kDiseaseCategories[disease] ?? const {});

  final candidates = <_Candidate>[];
  for (var i = 0; i < kCategoryPriority.length; i++) {
    final category = kCategoryPriority[i];
    if (matched.contains(category)) {
      candidates.add(_Candidate(repository.lookup(category, driver), true, i));
    }
  }
  // The cited default is always a baseline option.
  candidates.add(_Candidate(repository.lookup('*', '*'), false, kCategoryPriority.length));

  // De-duplicate by recommendation id, preserving the first (highest-priority)
  // occurrence — a matched advisory can coincide with the default.
  final seen = <String>{};
  final unique = <_Candidate>[
    for (final c in candidates)
      if (seen.add(c.recommendation.id)) c,
  ];

  final severity = _severityWeight(riskLevel);
  double scoreOf(_Candidate c) => (c.matches ? 2.0 : 0.0) + severity;

  unique.sort((a, b) {
    final byScore = scoreOf(b).compareTo(scoreOf(a));
    if (byScore != 0) return byScore;
    final byPriority = a.categoryIndex.compareTo(b.categoryIndex);
    if (byPriority != 0) return byPriority;
    return a.recommendation.id.compareTo(b.recommendation.id);
  });

  return [
    for (var i = 0; i < unique.length; i++)
      PrioritizedRecommendation(
        recommendation: unique[i].recommendation,
        rank: i + 1,
        matchesCondition: unique[i].matches,
        relevance: scoreOf(unique[i]),
      ),
  ];
}
