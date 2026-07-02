import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/weekly_report.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/weekly_report_use_case.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';

final _weekOf = DateTime.utc(2026, 6, 29);

RiskEstimateModel _risk() => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.medium,
  disease: 'Dengue',
  confidence: 0.72,
  temperature: 32.0,
  humidity: 70.0,
  aqi: 120.0,
  generatedAt: DateTime.utc(2026, 6, 29),
  modelVersion: 'rf-1.0.0',
);

AdherenceInsights _adherence() => const AdherenceInsights(
  currentStreakDays: 3,
  longestStreakDays: 5,
  takenCount: 10,
  missedCount: 1,
  strongestBucket: TimeOfDayBucket.morning,
  focusBucket: TimeOfDayBucket.evening,
);

const _recommendation = HealthRecommendation(
  id: 'rec-resp-air',
  category: 'respiratory',
  driver: 'Air quality',
  text: 'Limit prolonged outdoor exertion; a well-fitted N95 reduces exposure.',
  source: 'WHO — Air pollution',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  deepLink: '/resources',
  escalation: 'If breathing worsens, seek care; emergency → Rescue 1122.',
);

void main() {
  group('composeWeeklyReport — full data', () {
    test('ties risk, adherence and a cited recommendation into sections', () {
      final report = composeWeeklyReport(
        weekOf: _weekOf,
        risk: _risk(),
        trend: TrendDirection.rising,
        adherence: _adherence(),
        recommendation: _recommendation,
      );

      expect(report.city, 'Lahore');
      expect(report.hasRisk, isTrue);
      expect(report.isEmpty, isFalse);

      // Risk section: descriptive, names city/level/disease/confidence + trend.
      expect(report.riskSection.body, contains('Lahore'));
      expect(report.riskSection.body, contains('Medium'));
      expect(report.riskSection.body, contains('Dengue'));
      expect(report.riskSection.body, contains('72%'));
      expect(report.riskSection.body, contains('rising'));

      // Adherence section reuses the supportive copy (streak).
      expect(report.adherenceSection.body, contains('3-day streak'));

      // Cited recommendation carried verbatim.
      expect(report.recommendationSection, isNotNull);
      expect(report.recommendationSection!.body, _recommendation.text);
      expect(report.recommendation!.source, 'WHO — Air pollution');
    });

    test('is non-diagnostic — describes the environment, not the person', () {
      final body = composeWeeklyReport(
        weekOf: _weekOf,
        risk: _risk(),
        trend: TrendDirection.stable,
        adherence: _adherence(),
        recommendation: _recommendation,
      ).riskSection.body.toLowerCase();

      expect(body, contains('environment'));
      expect(body, isNot(contains('you have')));
      expect(body, isNot(contains('diagnos')));
    });

    test('is deterministic for identical inputs', () {
      WeeklyReportSection build() => composeWeeklyReport(
        weekOf: _weekOf,
        risk: _risk(),
        trend: TrendDirection.falling,
        adherence: _adherence(),
        recommendation: _recommendation,
      ).riskSection;
      expect(build(), build());
    });
  });

  group('composeWeeklyReport — partial / empty data states', () {
    test('no risk estimate → informative risk section, still composes', () {
      final report = composeWeeklyReport(
        weekOf: _weekOf,
        risk: null,
        trend: TrendDirection.insufficient,
        adherence: _adherence(),
        recommendation: _recommendation,
      );
      expect(report.hasRisk, isFalse);
      expect(report.city, isNull);
      expect(report.riskSection.body.toLowerCase(), contains("don’t have"));
      // Adherence still present.
      expect(report.adherenceSection.body, contains('3-day streak'));
    });

    test('no adherence logs → gentle empty adherence copy', () {
      final report = composeWeeklyReport(
        weekOf: _weekOf,
        risk: _risk(),
        trend: TrendDirection.stable,
        adherence: AdherenceInsights.empty(),
        recommendation: _recommendation,
      );
      expect(report.adherenceSection.body.toLowerCase(), contains('log a few doses'));
    });

    test('no recommendation → no recommendation section', () {
      final report = composeWeeklyReport(
        weekOf: _weekOf,
        risk: _risk(),
        trend: TrendDirection.stable,
        adherence: _adherence(),
        recommendation: null,
      );
      expect(report.recommendationSection, isNull);
    });

    test('nothing yet → isEmpty is true', () {
      final report = composeWeeklyReport(
        weekOf: _weekOf,
        risk: null,
        trend: TrendDirection.insufficient,
        adherence: AdherenceInsights.empty(),
        recommendation: null,
      );
      expect(report.isEmpty, isTrue);
    });
  });
}
