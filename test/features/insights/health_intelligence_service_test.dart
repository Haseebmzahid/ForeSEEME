import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_intelligence.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/health_intelligence_service.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';

const _service = HealthIntelligenceService();

RiskEstimateModel _estimate({
  String level = 'Low',
  double aqi = 80,
  double confidence = 0.82,
  bool withAttributions = false,
}) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevelX.fromJson(level),
  disease: 'Asthma',
  confidence: confidence,
  temperature: 30,
  humidity: 45,
  aqi: aqi,
  generatedAt: DateTime.utc(2026, 7, 18),
  modelVersion: 'rf-v1',
  attributions: withAttributions
      ? const RiskAttributions(
          method: 'tree_path',
          modelVersion: 'rf-1.0.0',
          disease: 'Asthma',
          predictedClass: 'Low',
          baseValue: 0.3,
          topContributors: [],
          confidenceRationale: ConfidenceRationale(
            confidence: 0.82,
            predictedClass: 'Low',
            runnerUpClass: 'Medium',
            runnerUpConfidence: 0.1,
            margin: 0.7,
            agreement: 0.9,
            strength: ConfidenceStrength.strong,
            lowConfidence: false,
          ),
        )
      : null,
);

AdherenceInsights _adherence({int taken = 12, int missed = 1}) =>
    AdherenceInsights(
      currentStreakDays: 4,
      longestStreakDays: 6,
      takenCount: taken,
      missedCount: missed,
      strongestBucket: TimeOfDayBucket.morning,
      focusBucket: TimeOfDayBucket.evening,
    );

WeeklyReflection _reflection({int percent = 92, int delta = 8}) =>
    WeeklyReflection(
      adherencePercent: percent,
      comparedToLastWeek: delta,
      longestStreak: 6,
      missedDoses: 1,
      bestDay: 'Monday',
      needsAttention: null,
    );

TodaysMission _mission(MissionState state) => TodaysMission(
  state: state,
  title: 'Mission',
  message: 'msg',
  medicationName: null,
  rawDeadlineTime: null,
  currentStreak: 4,
);

DayJourneyCard _today({
  DoseCompletionState morning = DoseCompletionState.taken,
  DoseCompletionState evening = DoseCompletionState.pending,
}) => DayJourneyCard(
  date: DateTime.utc(2026, 7, 18),
  weekdayLabel: 'Sat',
  isToday: true,
  status: DayJourneyStatus.today,
  morning: morning,
  evening: evening,
  completedDoses: 1,
  totalDoses: 2,
  missedDoses: 0,
  adherencePercent: 50,
  supportingMessage: 'msg',
);

EnvironmentalDriver _driver(
  String feature,
  String label, {
  ContributionDirection direction = ContributionDirection.increases,
  double magnitude = 0.4,
}) => EnvironmentalDriver(
  feature: feature,
  label: label,
  direction: direction,
  magnitude: magnitude,
);

void main() {
  group('HealthIntelligenceService.compose — summary', () {
    test('low risk with a real estimate → labelled, confident, stable copy', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(level: 'Low', confidence: 0.82),
        trend: TrendDirection.stable,
        adherence: _adherence(),
        reflection: _reflection(),
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: const [],
      );

      expect(view.summary.hasEstimate, isTrue);
      expect(view.summary.levelLabel, 'Low Risk');
      expect(view.summary.confidencePercent, 82);
      expect(view.summary.assessment, contains('Lahore'));
      expect(view.whyTitle, 'Why is your risk low?');
      expect(view.isHighRisk, isFalse);
    });

    test('no estimate → honest pending summary, no fabricated reading', () {
      final view = _service.compose(
        city: null,
        estimate: null,
        trend: TrendDirection.insufficient,
        adherence: AdherenceInsights.empty(),
        reflection: null,
        mission: _mission(MissionState.noMedications),
        today: null,
        drivers: const [],
      );

      expect(view.summary.hasEstimate, isFalse);
      expect(view.summary.levelLabel, 'Assessment pending');
      expect(view.summary.confidencePercent, isNull);
      expect(view.whyTitle, 'What shapes your risk?');
      expect(view.environment.hasData, isFalse);
      expect(view.isHighRisk, isFalse);
    });

    test('high risk flags the emergency affordance', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(level: 'High', aqi: 260),
        trend: TrendDirection.rising,
        adherence: _adherence(),
        reflection: _reflection(delta: -5),
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: const [],
      );
      expect(view.isHighRisk, isTrue);
      expect(view.summary.levelLabel, 'High Risk');
    });
  });

  group('HealthIntelligenceService.compose — why reasons', () {
    test('improving adherence, easing driver, falling trend → all positive', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(level: 'Low', aqi: 80),
        trend: TrendDirection.falling,
        adherence: _adherence(),
        reflection: _reflection(delta: 8),
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: [
          _driver(
            'temperature',
            'Temperature',
            direction: ContributionDirection.decreases,
          ),
        ],
      );

      expect(view.whyReasons, isNotEmpty);
      expect(
        view.whyReasons.every((r) => r.tone == ReasonTone.positive),
        isTrue,
      );
      expect(
        view.whyReasons.first.text,
        'Your medication adherence is improving',
      );
      expect(
        view.whyReasons.map((r) => r.text),
        contains('Your area’s recent risk trend is easing'),
      );
    });

    test('a rising AQI driver is not duplicated by a separate AQI reason', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(level: 'Medium', aqi: 180),
        trend: TrendDirection.stable,
        adherence: AdherenceInsights.empty(),
        reflection: null,
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: [_driver('us_aqi', 'Air quality (AQI)')],
      );

      final aqiMentions = view.whyReasons
          .where((r) => r.text.toLowerCase().contains('air quality'))
          .length;
      expect(aqiMentions, 1);
    });

    test('no adherence data → no fabricated medication reason', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(),
        trend: TrendDirection.insufficient,
        adherence: AdherenceInsights.empty(),
        reflection: null,
        mission: _mission(MissionState.noMedications),
        today: null,
        drivers: const [],
      );
      expect(
        view.whyReasons.any((r) => r.text.toLowerCase().contains('adherence')),
        isFalse,
      );
    });
  });

  group('HealthIntelligenceService.compose — contributors', () {
    test('medication + environment are live; symptoms + peak flow coming soon', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(level: 'Low', aqi: 40),
        trend: TrendDirection.stable,
        adherence: _adherence(),
        reflection: _reflection(percent: 92),
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: const [],
      );

      final byKey = {for (final c in view.contributors) c.key: c};
      expect(byKey.keys, containsAll(['medication', 'environment', 'symptoms', 'peak_flow']));

      expect(byKey['medication']!.status, ContributorStatus.excellent);
      expect(byKey['medication']!.because, '92% adherence this week.');
      expect(byKey['environment']!.status, ContributorStatus.excellent); // AQI 40 = good

      // Honest roadmap items — never a fabricated reading.
      expect(byKey['symptoms']!.status, ContributorStatus.comingSoon);
      expect(byKey['peak_flow']!.status, ContributorStatus.comingSoon);
      expect(byKey['symptoms']!.isComingSoon, isTrue);
    });

    test('no data → medication + environment degrade to "unavailable"', () {
      final view = _service.compose(
        city: null,
        estimate: null,
        trend: TrendDirection.insufficient,
        adherence: AdherenceInsights.empty(),
        reflection: null,
        mission: _mission(MissionState.noMedications),
        today: null,
        drivers: const [],
      );
      final byKey = {for (final c in view.contributors) c.key: c};
      expect(byKey['medication']!.status, ContributorStatus.unavailable);
      expect(byKey['environment']!.status, ContributorStatus.unavailable);
    });
  });

  group('HealthIntelligenceService.compose — trend changes', () {
    test('real weekly adherence delta + risk direction + streak', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(level: 'Low'),
        trend: TrendDirection.falling,
        adherence: _adherence(),
        reflection: _reflection(delta: 8),
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: const [],
      );

      final adherence = view.trendChanges
          .firstWhere((c) => c.label == 'Medication adherence');
      expect(adherence.direction, TrendChangeDirection.improved);
      expect(adherence.detail, 'improved 8%');

      final risk = view.trendChanges.firstWhere((c) => c.label == 'Asthma risk');
      expect(risk.direction, TrendChangeDirection.improved);
      expect(risk.detail, 'decreased');

      expect(view.trendChanges.any((c) => c.label == 'Longest streak'), isTrue);
    });

    test('insufficient trend and no reflection → no invented changes', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(),
        trend: TrendDirection.insufficient,
        adherence: AdherenceInsights.empty(),
        reflection: null,
        mission: _mission(MissionState.noMedications),
        today: null,
        drivers: const [],
      );
      expect(view.trendChanges, isEmpty);
    });
  });

  group('HealthIntelligenceService.compose — timeline', () {
    test('builds morning/afternoon/evening/tomorrow from real states', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(aqi: 120),
        trend: TrendDirection.stable,
        adherence: _adherence(),
        reflection: _reflection(),
        mission: _mission(MissionState.pending),
        today: _today(
          morning: DoseCompletionState.taken,
          evening: DoseCompletionState.pending,
        ),
        drivers: const [],
      );

      expect(view.timeline.map((e) => e.period), [
        'Morning',
        'Afternoon',
        'Evening',
        'Tomorrow',
      ]);
      expect(view.timeline[0].marker, TimelineMarker.done);
      expect(view.timeline[1].marker, TimelineMarker.info); // AQI marker
      expect(view.timeline[2].marker, TimelineMarker.pending);
      expect(view.timeline[3].marker, TimelineMarker.upcoming);
    });

    test('no journey + no estimate → still a forward-looking tomorrow line', () {
      final view = _service.compose(
        city: null,
        estimate: null,
        trend: TrendDirection.insufficient,
        adherence: AdherenceInsights.empty(),
        reflection: null,
        mission: _mission(MissionState.noMedications),
        today: null,
        drivers: const [],
      );
      expect(view.timeline, hasLength(1));
      expect(view.timeline.single.period, 'Tomorrow');
    });
  });

  group('HealthIntelligenceService.compose — environmental context', () {
    test('carries stored AQI/weather + the top driver as the primary trigger', () {
      final view = _service.compose(
        city: 'Lahore',
        estimate: _estimate(aqi: 165),
        trend: TrendDirection.stable,
        adherence: _adherence(),
        reflection: _reflection(),
        mission: _mission(MissionState.pending),
        today: _today(),
        drivers: [_driver('us_aqi', 'Air quality (AQI)')],
      );

      expect(view.environment.hasData, isTrue);
      expect(view.environment.aqi, 165);
      expect(view.environment.aqiBandLabel, 'Unhealthy');
      expect(view.environment.temperatureC, 30);
      expect(view.environment.primaryTriggerLabel, 'Air quality (AQI)');
      expect(view.environment.primaryTriggerNote, contains('Lahore'));
    });
  });
}
