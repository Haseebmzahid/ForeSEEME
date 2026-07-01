import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_details_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_trend_chart.dart';

RiskEstimateModel _est({
  required String level,
  String disease = 'Smog',
  String date = '2026-06-30',
  double confidence = 0.89,
  double aqi = 184,
}) => RiskEstimateModel.fromJson({
  'city': 'Lahore',
  'riskLevel': level,
  'disease': disease,
  'confidence': confidence,
  'temperature': 30.0,
  'humidity': 40.0,
  'aqi': aqi,
  'generatedAt': '${date}T00:00:00.000Z',
  'modelVersion': 'rf-v1',
});

const _rec = HealthRecommendation(
  id: 'rec-resp-air',
  category: 'respiratory',
  driver: 'Air quality',
  text: 'Limit outdoor exertion and keep a mask handy.',
  source: 'WHO — Air pollution',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  deepLink: '/resources',
  escalation: 'If breathing worsens, seek care; emergency → Rescue 1122.',
);

/// Builds the screen with every screen-facing provider overridden (so no test
/// touches real Firebase). `trend` drives the hero badge + summary.
Widget _screen({
  required RiskEstimateModel? estimate,
  List<RiskEstimateModel>? history,
  Object? historyError,
  TrendDirection trend = TrendDirection.insufficient,
}) {
  return ProviderScope(
    overrides: [
      currentCityRiskProvider.overrideWith((ref) async => estimate),
      currentCityRiskHistoryProvider.overrideWith((ref) async {
        if (historyError != null) throw historyError;
        return history ?? const [];
      }),
      riskTrendProvider.overrideWith((ref) async => trend),
      currentRecommendationProvider.overrideWith((ref) => _rec),
    ],
    child: const MaterialApp(home: RiskDetailsScreen()),
  );
}

/// Pumps on a tall surface (so the lazy ListView builds every section) and
/// settles.
///
/// `pumpAndSettle` is safe here **because every provider the screen reads is
/// overridden to resolve** (see [_screen]): the transient loading `Shimmer`s
/// (whose `AnimationController.repeat()` would otherwise never idle) unmount as
/// soon as their providers resolve, and the only remaining animations are the
/// finite chart-draw / fade tweens. `fl_chart` runs with `duration: Duration.zero`,
/// so it schedules no animation frames.
Future<void> _pump(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

/// Six weekly estimates rising Low→High (real, ordered oldest→newest).
List<RiskEstimateModel> _risingHistory() => [
  _est(level: 'Low', date: '2026-05-26'),
  _est(level: 'Low', date: '2026-06-02'),
  _est(level: 'Medium', date: '2026-06-09'),
  _est(level: 'Medium', date: '2026-06-16'),
  _est(level: 'High', date: '2026-06-23'),
  _est(level: 'High', date: '2026-06-30'),
];

List<RiskEstimateModel> _fallingHistory() => [
  _est(level: 'High', date: '2026-05-26'),
  _est(level: 'High', date: '2026-06-02'),
  _est(level: 'Medium', date: '2026-06-09'),
  _est(level: 'Medium', date: '2026-06-16'),
  _est(level: 'Low', date: '2026-06-23'),
  _est(level: 'Low', date: '2026-06-30'),
];

List<RiskEstimateModel> _stableHistory() => [
  for (final d in [
    '2026-05-26',
    '2026-06-02',
    '2026-06-09',
    '2026-06-16',
    '2026-06-23',
    '2026-06-30',
  ])
    _est(level: 'Medium', date: d),
];

void main() {
  group('RiskDetailsScreen', () {
    testWidgets('renders hero + chart when history is available', (
      tester,
    ) async {
      await _pump(
        tester,
        _screen(
          estimate: _est(level: 'High'),
          history: _risingHistory(),
          trend: TrendDirection.rising,
        ),
      );

      expect(find.text('High Risk'), findsOneWidget); // hero
      expect(find.text('Lahore · Smog'), findsOneWidget);
      expect(find.byType(RiskTrendChart), findsOneWidget); // chart drawn
      expect(find.text('Primary driver'), findsOneWidget);
      expect(find.text('Confidence'), findsOneWidget);
      expect(find.text('What you can do'), findsOneWidget);
      expect(find.textContaining('mask handy'), findsOneWidget);
    });

    testWidgets('rising history shows a "Rising" summary', (tester) async {
      await _pump(
        tester,
        _screen(
          estimate: _est(level: 'High'),
          history: _risingHistory(),
          trend: TrendDirection.rising,
        ),
      );
      expect(find.textContaining('Rising'), findsWidgets);
      expect(find.byType(RiskTrendChart), findsOneWidget);
    });

    testWidgets('falling history shows an "Improving" summary', (tester) async {
      await _pump(
        tester,
        _screen(
          estimate: _est(level: 'Low'),
          history: _fallingHistory(),
          trend: TrendDirection.falling,
        ),
      );
      expect(find.textContaining('Improving'), findsOneWidget);
    });

    testWidgets('stable history shows a "Stable" summary', (tester) async {
      await _pump(
        tester,
        _screen(
          estimate: _est(level: 'Medium'),
          history: _stableHistory(),
          trend: TrendDirection.stable,
        ),
      );
      // Shown by both the trend badge and the summary line.
      expect(find.textContaining('Stable'), findsWidgets);
    });

    testWidgets('too little history → informative empty state, no chart', (
      tester,
    ) async {
      await _pump(
        tester,
        _screen(
          estimate: _est(level: 'High'),
          history: [_est(level: 'High')],
        ),
      );

      expect(find.text('No historical trend available yet.'), findsOneWidget);
      expect(find.byType(RiskTrendChart), findsNothing); // never an empty chart
      expect(find.text('High Risk'), findsOneWidget); // hero still renders
    });

    testWidgets('chart error → retry action, no crash', (tester) async {
      await _pump(
        tester,
        _screen(
          estimate: _est(level: 'High'),
          historyError: Exception('offline'),
        ),
      );

      expect(find.textContaining("Couldn't load the trend"), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });

    testWidgets('no current estimate → no-risk empty state', (tester) async {
      await _pump(tester, _screen(estimate: null));

      expect(find.text('No risk data yet'), findsOneWidget);
      expect(find.byType(RiskTrendChart), findsNothing);
    });
  });

  // End-to-end read path: the chart renders from REAL Firestore documents
  // (the exact contract shape the backend `compute_risk backfill` writes),
  // through the real repository + providers — history is NOT overridden here.
  group('RiskDetailsScreen — real Firestore read path (backfilled docs)', () {
    Map<String, dynamic> doc(String level, String date) => {
      'city': 'Lahore',
      'riskLevel': level,
      'disease': 'Smog',
      'confidence': 0.87,
      'temperature': 32.0,
      'humidity': 45.0,
      'aqi': 180.0,
      'generatedAt': '${date}T00:00:00.000Z',
      'modelVersion': 'rf-1.0.0',
      'lowConfidence': false,
    };

    Future<FakeFirebaseFirestore> seedSixWeeks() async {
      final fs = FakeFirebaseFirestore();
      const rows = [
        ['Low', '2026-05-25'],
        ['Low', '2026-06-01'],
        ['Medium', '2026-06-08'],
        ['Medium', '2026-06-15'],
        ['High', '2026-06-22'],
        ['High', '2026-06-29'],
      ];
      for (final r in rows) {
        await fs
            .collection('riskEstimates')
            .doc('Lahore_${r[1]}')
            .set(doc(r[0], r[1]));
      }
      return fs;
    }

    testWidgets('renders the chart from 6 real historical documents', (
      tester,
    ) async {
      final firestore = await seedSixWeeks();

      await _pump(
        tester,
        ProviderScope(
          overrides: [
            userCityProvider.overrideWith((ref) async => 'Lahore'),
            riskRepositoryProvider.overrideWithValue(
              FirestoreRiskRepository(firestore: firestore),
            ),
            currentRecommendationProvider.overrideWith((ref) => _rec),
          ],
          child: const MaterialApp(home: RiskDetailsScreen()),
        ),
      );

      // Hero from the latest real doc + the chart from the real 6-week history.
      expect(find.text('High Risk'), findsOneWidget);
      expect(find.byType(RiskTrendChart), findsOneWidget);
      expect(find.text('No historical trend available yet.'), findsNothing);
    });

    testWidgets('a single real document → informative empty state, no chart', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('riskEstimates')
          .doc('Lahore_2026-06-29')
          .set(doc('High', '2026-06-29'));

      await _pump(
        tester,
        ProviderScope(
          overrides: [
            userCityProvider.overrideWith((ref) async => 'Lahore'),
            riskRepositoryProvider.overrideWithValue(
              FirestoreRiskRepository(firestore: firestore),
            ),
            currentRecommendationProvider.overrideWith((ref) => _rec),
          ],
          child: const MaterialApp(home: RiskDetailsScreen()),
        ),
      );

      expect(find.text('High Risk'), findsOneWidget); // hero still shows
      expect(find.text('No historical trend available yet.'), findsOneWidget);
      expect(find.byType(RiskTrendChart), findsNothing);
    });
  });
}
