import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_prioritizer.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

const _repo = StaticRecommendationRepository();

List<String> _ids(List<PrioritizedRecommendation> list) =>
    list.map((p) => p.recommendation.id).toList();

void main() {
  test('every result is cited (never generated)', () {
    final ranked = prioritizeRecommendations(
      riskLevel: RiskLevel.high,
      disease: 'Smog',
      conditions: const ['Asthma'],
      repository: _repo,
    );
    for (final item in ranked) {
      expect(item.recommendation.source, isNotEmpty);
      expect(item.recommendation.sourceUrl, startsWith('https://'));
    }
  });

  test('condition-matched advisory outranks the general default', () {
    final ranked = prioritizeRecommendations(
      riskLevel: RiskLevel.high,
      disease: 'Smog', // driver = Air quality; respiratory vulnerable
      conditions: const ['Asthma'], // respiratory
      repository: _repo,
    );

    expect(ranked.first.recommendation.id, 'rec-resp-air');
    expect(ranked.first.matchesCondition, isTrue);
    expect(ranked.first.rank, 1);
    // The cited default is present but ranked below the matched advisory.
    expect(ranked.last.recommendation.id, 'rec-default');
    expect(ranked.last.matchesCondition, isFalse);
    expect(ranked.first.relevance, greaterThan(ranked.last.relevance));
  });

  test('multiple matched categories are ordered by category priority', () {
    // Smog makes BOTH respiratory and cardiovascular vulnerable; a user with a
    // condition in each gets both advisories, respiratory first (priority).
    final ranked = prioritizeRecommendations(
      riskLevel: RiskLevel.high,
      disease: 'Smog',
      conditions: const ['Asthma', 'Heart Disease'],
      repository: _repo,
    );

    expect(_ids(ranked), ['rec-resp-air', 'rec-cardio-air', 'rec-default']);
    expect(ranked.map((p) => p.rank).toList(), [1, 2, 3]);
  });

  test('no matching condition → only the cited default', () {
    // Dengue has no in-scope chronic-condition driver.
    final ranked = prioritizeRecommendations(
      riskLevel: RiskLevel.medium,
      disease: 'Dengue',
      conditions: const ['Asthma'],
      repository: _repo,
    );
    expect(_ids(ranked), ['rec-default']);
    expect(ranked.single.rank, 1);
  });

  test('is deterministic for identical inputs', () {
    List<String> run() => _ids(
      prioritizeRecommendations(
        riskLevel: RiskLevel.high,
        disease: 'Smog',
        conditions: const ['Heart Disease', 'Asthma'], // order should not matter
        repository: _repo,
      ),
    );
    expect(run(), run());
    // Condition list order does not change the deterministic result.
    final reversed = _ids(
      prioritizeRecommendations(
        riskLevel: RiskLevel.high,
        disease: 'Smog',
        conditions: const ['Asthma', 'Heart Disease'],
        repository: _repo,
      ),
    );
    expect(run(), reversed);
  });

  test('higher severity lifts the relevance score', () {
    double topScore(RiskLevel level) => prioritizeRecommendations(
      riskLevel: level,
      disease: 'Smog',
      conditions: const ['Asthma'],
      repository: _repo,
    ).first.relevance;

    expect(topScore(RiskLevel.high), greaterThan(topScore(RiskLevel.low)));
  });
}
