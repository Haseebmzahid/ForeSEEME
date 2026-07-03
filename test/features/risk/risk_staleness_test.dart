import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_staleness.dart';

// Fixed reference instant so every case is deterministic regardless of the
// machine clock (the util takes an injectable `now`).
final _now = DateTime.utc(2026, 7, 2, 12);

RiskEstimateModel _est(DateTime generatedAt) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.high,
  disease: 'Smog',
  confidence: 0.9,
  temperature: 32,
  humidity: 45,
  aqi: 180,
  generatedAt: generatedAt,
  modelVersion: 'rf-1.0.0',
);

void main() {
  group('riskFreshness / isRiskStale', () {
    test('a recent estimate is fresh', () {
      final g = _now.subtract(const Duration(days: 2));
      expect(riskFreshness(g, now: _now), RiskFreshness.fresh);
      expect(isRiskStale(g, now: _now), isFalse);
    });

    test('an old estimate is stale', () {
      final g = _now.subtract(const Duration(days: 30));
      expect(riskFreshness(g, now: _now), RiskFreshness.stale);
      expect(isRiskStale(g, now: _now), isTrue);
    });

    test('the boundary is exclusive: exactly 9 days is still fresh', () {
      final exactly = _now.subtract(kRiskStaleAfter);
      expect(isRiskStale(exactly, now: _now), isFalse);

      // A moment past the threshold flips to stale.
      final justOver = _now.subtract(kRiskStaleAfter + const Duration(minutes: 1));
      expect(isRiskStale(justOver, now: _now), isTrue);
    });

    test('threshold is the documented 9 days (weekly cadence + grace)', () {
      expect(kRiskStaleAfter, const Duration(days: 9));
    });

    test('comparison is UTC-normalised regardless of the input offset', () {
      // Same instant expressed in a +05:00 local offset must classify the same.
      final utcOld = _now.subtract(const Duration(days: 30));
      final localOld = utcOld.toLocal();
      expect(
        riskFreshness(localOld, now: _now),
        riskFreshness(utcOld, now: _now),
      );
    });

    test('estimateFreshness reads the model timestamp', () {
      expect(
        estimateFreshness(_est(_now.subtract(const Duration(days: 30))),
            now: _now),
        RiskFreshness.stale,
      );
    });
  });

  group('riskAgeLabel', () {
    test('very recent reads "just now"', () {
      expect(
        riskAgeLabel(_now.subtract(const Duration(seconds: 30)), now: _now),
        'just now',
      );
    });

    test('minutes, hours and days are humanised', () {
      expect(
        riskAgeLabel(_now.subtract(const Duration(minutes: 20)), now: _now),
        '20 min ago',
      );
      expect(
        riskAgeLabel(_now.subtract(const Duration(hours: 3)), now: _now),
        '3h ago',
      );
      expect(
        riskAgeLabel(_now.subtract(const Duration(days: 1)), now: _now),
        '1 day ago',
      );
      expect(
        riskAgeLabel(_now.subtract(const Duration(days: 5)), now: _now),
        '5 days ago',
      );
    });

    test('clock skew (a future timestamp) degrades to "just now"', () {
      expect(
        riskAgeLabel(_now.add(const Duration(hours: 2)), now: _now),
        'just now',
      );
    });
  });
}
