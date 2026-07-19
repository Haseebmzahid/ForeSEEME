import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_intelligence.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/health_intelligence_service.dart';
import 'package:fyp_foreseeme/features/insights/presentation/health_intelligence_screen.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/adherence_journey_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

const _service = HealthIntelligenceService();

const _rec = HealthRecommendation(
  id: 'rec-resp-air',
  category: 'respiratory',
  driver: 'Air quality',
  text: 'Keep windows closed during peak smog.',
  source: 'WHO — Air pollution',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  deepLink: '/resources',
  escalation: 'If breathing worsens, seek care; emergency → Rescue 1122.',
);

RiskEstimateModel _estimate(String level, double aqi) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevelX.fromJson(level),
  disease: 'Asthma',
  confidence: 0.82,
  temperature: 33,
  humidity: 40,
  aqi: aqi,
  generatedAt: DateTime.utc(2026, 7, 18),
  modelVersion: 'rf-v1',
  attributions: const RiskAttributions(
    method: 'tree_path',
    modelVersion: 'rf-1.0.0',
    disease: 'Asthma',
    predictedClass: 'High',
    baseValue: 0.3,
    topContributors: [
      FeatureContribution(
        feature: 'us_aqi',
        contribution: 0.22,
        magnitude: 0.22,
        direction: ContributionDirection.increases,
        value: 210,
      ),
    ],
    confidenceRationale: ConfidenceRationale(
      confidence: 0.82,
      predictedClass: 'High',
      runnerUpClass: 'Medium',
      runnerUpConfidence: 0.12,
      margin: 0.7,
      agreement: 0.9,
      strength: ConfidenceStrength.strong,
      lowConfidence: false,
    ),
  ),
);

HealthIntelligenceView _view(RiskEstimateModel? estimate) => _service.compose(
  city: 'Lahore',
  estimate: estimate,
  trend: TrendDirection.stable,
  adherence: const AdherenceInsights(
    currentStreakDays: 4,
    longestStreakDays: 6,
    takenCount: 12,
    missedCount: 1,
    strongestBucket: TimeOfDayBucket.morning,
    focusBucket: TimeOfDayBucket.evening,
  ),
  reflection: const WeeklyReflection(
    adherencePercent: 92,
    comparedToLastWeek: 8,
    longestStreak: 6,
    missedDoses: 1,
    bestDay: 'Monday',
    needsAttention: null,
  ),
  mission: const TodaysMission(
    state: MissionState.pending,
    title: 'Evening dose',
    message: 'Take it before 9 PM',
    medicationName: 'Ventolin',
    rawDeadlineTime: '21:00',
    currentStreak: 4,
  ),
  today: DayJourneyCard(
    date: DateTime.utc(2026, 7, 18),
    weekdayLabel: 'Sat',
    isToday: true,
    status: DayJourneyStatus.today,
    morning: DoseCompletionState.taken,
    evening: DoseCompletionState.pending,
    completedDoses: 1,
    totalDoses: 2,
    missedDoses: 0,
    adherencePercent: 50,
    supportingMessage: 'msg',
  ),
  drivers: deriveEnvironmentalDrivers(estimate?.attributions),
);

Widget _screen(RiskEstimateModel? estimate) => ProviderScope(
  overrides: [
    healthIntelligenceProvider.overrideWith((ref) async => _view(estimate)),
    currentCityRiskProvider.overrideWith((ref) async => estimate),
    currentRecommendationProvider.overrideWith((ref) => _rec),
  ],
  child: const MaterialApp(home: HealthIntelligenceScreen()),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('HealthIntelligenceScreen', () {
    testWidgets('composes every explanation section with a disclaimer', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_screen(_estimate('Low', 40)));
      await tester.pumpAndSettle();

      // Section 1 — summary
      expect(find.text("TODAY'S HEALTH SUMMARY"), findsOneWidget);
      expect(find.text('Low Risk'), findsWidgets);

      // Section 2 — the signature "Why?" question
      expect(find.text('Why is your risk low?'), findsOneWidget);

      // Section 3 — contributors, including the honest coming-soon items
      expect(find.text('WHAT AFFECTS YOU'), findsOneWidget);
      expect(find.text('Symptoms'), findsOneWidget);
      expect(find.text('Peak Flow'), findsOneWidget);
      expect(find.text('Coming soon'), findsWidgets);

      // Section 4 — cited recommendation (never generated)
      expect(find.text('Source: WHO — Air pollution'), findsOneWidget);

      // Sections 5–7 headers/labels
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text("Today's Timeline"), findsOneWidget);
      expect(find.text('ENVIRONMENT'), findsOneWidget);
      expect(find.text('LEARN MORE'), findsOneWidget);

      // Always-pinned non-diagnostic framing
      expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
    });

    testWidgets('a coming-soon contributor expands to its roadmap note', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_screen(_estimate('Low', 40)));
      await tester.pumpAndSettle();

      // Medication contributor is expandable (has a Learn more link).
      await tester.tap(find.text('Medication'));
      await tester.pumpAndSettle();
      expect(find.text('Medication tips'), findsOneWidget);
    });

    testWidgets('high risk surfaces the emergency affordance', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_screen(_estimate('High', 260)));
      await tester.pumpAndSettle();

      expect(find.text('High Risk'), findsWidgets);
      expect(find.textContaining('Emergency ·'), findsOneWidget);
    });

    testWidgets('low risk hides the emergency affordance', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_screen(_estimate('Low', 40)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Emergency ·'), findsNothing);
    });
  });
}
