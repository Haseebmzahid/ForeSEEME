// End-to-end proactive pipeline — the Flutter read legs (Sprint 5, Prompt 16):
// **store → read → explain**, **receive → inbox**, and the **staleness** signal.
//
// This drives the REAL app read path over a single fake Firestore seeded with the
// exact documents a real backend run produces: a `riskEstimates` doc carrying the
// additive `attributions` object (what `compute_risk` writes), and the `userAlerts`
// inbox doc (what `dispatch_alerts` writes). It proves the app consumes the
// backend's contract — the risk renders, the stored attributions are explained in
// plain language, the delivered alert surfaces in the owner's inbox, and an old
// estimate is labelled stale rather than shown as current.
//
// Complements `backend/tests/test_e2e_pipeline.py` (predict → attribute → store →
// dispatch → inbox) and `test/integration/alert_pipeline_e2e_test.dart` (the inbox
// mark-read + deep-link engagement leg).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_override_repository.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_details_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/explanation_panel.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

const _uid = 'asthma_ok';
const _logId = 'asthma_ok__Lahore_2026-06-30__respiratory';

UserModel _user() =>
    UserModel(uid: _uid, email: '$_uid@b.com', createdAt: DateTime.utc(2026, 1, 1));

/// A `riskEstimates` document with the backend's additive `attributions` object.
Map<String, dynamic> _estimateDoc({
  required String riskLevel,
  required DateTime generatedAt,
}) => {
  'city': 'Lahore',
  'riskLevel': riskLevel,
  'disease': 'Smog',
  'confidence': 0.82,
  'temperature': 34.0,
  'humidity': 55.0,
  'aqi': 184.0,
  'generatedAt': generatedAt.toUtc().toIso8601String(),
  'modelVersion': 'rf-1.0.0',
  'lowConfidence': false,
  'attributions': {
    'method': 'tree_path_contributions',
    'modelVersion': 'rf-1.0.0',
    'disease': 'smog',
    'predictedClass': riskLevel,
    'baseValue': 0.33,
    'topContributors': [
      {
        'feature': 'temperature',
        'contribution': 0.44,
        'magnitude': 0.44,
        'direction': 'increases',
        'value': 34.0,
      },
      {
        'feature': 'humidity_lag1',
        'contribution': -0.07,
        'magnitude': 0.07,
        'direction': 'decreases',
        'value': 55.0,
      },
    ],
    'confidenceRationale': {
      'confidence': 0.82,
      'predictedClass': riskLevel,
      'runnerUpClass': 'Medium',
      'runnerUpConfidence': 0.14,
      'margin': 0.68,
      'agreement': 0.9,
      'strength': 'strong',
      'lowConfidence': false,
    },
  },
};

/// The `userAlerts` inbox document the dispatch engine writes for this estimate.
Map<String, dynamic> _alertDoc() => {
  'title': 'Air quality rising in Lahore',
  'body': 'High Smog risk. Limit outdoor activity.',
  'category': 'respiratory',
  'city': 'Lahore',
  'riskLevel': 'High',
  'disease': 'Smog',
  'recommendation': {
    'id': 'rec-resp-air',
    'text': 'Keep windows closed during peak smog.',
    'source': 'WHO — Air pollution',
    'sourceUrl': 'https://www.who.int/health-topics/air-pollution',
  },
  'deepLink': '/resources',
  'riskEstimateId': 'Lahore_2026-06-30',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 30, 12)),
  'read': false,
  'readAt': null,
};

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

Future<FakeFirebaseFirestore> _seed({
  required String riskLevel,
  required DateTime generatedAt,
  bool withAlert = false,
}) async {
  final fs = FakeFirebaseFirestore();
  await fs
      .collection('riskEstimates')
      .doc('Lahore_${generatedAt.toUtc().toIso8601String().substring(0, 10)}')
      .set(_estimateDoc(riskLevel: riskLevel, generatedAt: generatedAt));
  if (withAlert) {
    await fs
        .collection('userAlerts')
        .doc(_uid)
        .collection('items')
        .doc(_logId)
        .set(_alertDoc());
  }
  return fs;
}

Future<void> _pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  // The shared scope overrides for the read surfaces. Declared as a LOCAL
  // function (not top-level): `flutter_riverpod` 3.3.1 does not export the
  // `Override` type, so the `List<Override>` returned here has no writable type
  // name — Riverpod 3's intended pattern is inference. Keeping it local means the
  // list type is still inferred strongly (no `dynamic`) while staying outside the
  // scope of `strict_top_level_inference`, which only targets top-level/class
  // declarations.
  buildOverrides(FakeFirebaseFirestore fs) => [
    userCityProvider.overrideWith((ref) async => 'Lahore'),
    riskRepositoryProvider.overrideWithValue(
      FirestoreRiskRepository(firestore: fs),
    ),
    // No operator override in force → the genuine estimate shows through.
    riskOverrideRepositoryProvider.overrideWithValue(
      FirestoreRiskOverrideRepository(firestore: fs),
    ),
    currentRecommendationProvider.overrideWith((ref) => _rec),
  ];

  group('proactive pipeline e2e — read → explain → inbox → staleness', () {
    testWidgets('stored estimate + attributions is read and EXPLAINED', (
      tester,
    ) async {
      final fs = await _seed(
        riskLevel: 'High',
        generatedAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );

      await _pumpTall(
        tester,
        ProviderScope(
          overrides: buildOverrides(fs),
          child: const MaterialApp(home: RiskDetailsScreen()),
        ),
      );

      // Risk read from the stored doc.
      expect(find.text('High Risk'), findsOneWidget);
      // The backend's stored attributions, explained in plain language (Prompt 6)
      // — genuine drivers, in the backend's order, never fabricated. Scope to the
      // ExplanationPanel: "Temperature" also legitimately renders as the
      // dashboard's primary-driver value (Prompt 6 added the second surface), so
      // assert the driver is explained *inside the explanation panel*.
      final explanation = find.byType(ExplanationPanel);
      expect(explanation, findsOneWidget);
      expect(find.text('Why this estimate?'), findsOneWidget);
      expect(
        find.descendant(of: explanation, matching: find.text('Temperature')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: explanation,
          matching: find.byIcon(Icons.arrow_upward_rounded),
        ),
        findsOneWidget,
      );
    });

    test('the delivered alert surfaces in the owner inbox (receive → inbox)', () async {
      final fs = await _seed(
        riskLevel: 'High',
        generatedAt: DateTime.now().toUtc(),
        withAlert: true,
      );
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_user())),
          userAlertsRepositoryProvider.overrideWithValue(
            FirestoreUserAlertsRepository(firestore: fs),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(userAlertsStreamProvider, (_, _) {}, fireImmediately: true);

      final alerts = await container.read(userAlertsStreamProvider.future);
      expect(alerts, hasLength(1));
      expect(alerts.single.title, 'Air quality rising in Lahore');
      // The inbox alert is tied to the same estimate the risk surfaces read.
      expect(alerts.single.riskEstimateId, 'Lahore_2026-06-30');
      expect(container.read(unreadAlertCountProvider), 1);
    });

    testWidgets('a STALE estimate is labelled, not shown as current', (
      tester,
    ) async {
      // Older than kRiskStaleAfter (9 days) → must be flagged.
      final fs = await _seed(
        riskLevel: 'High',
        generatedAt: DateTime.now().toUtc().subtract(const Duration(days: 30)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...buildOverrides(fs),
            riskTrendProvider.overrideWith((ref) async => TrendDirection.stable),
          ],
          child: const MaterialApp(home: Scaffold(body: Center(child: RiskCard()))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('High Risk'), findsOneWidget);
      expect(find.text('This estimate may be out of date'), findsOneWidget);
    });
  });
}
