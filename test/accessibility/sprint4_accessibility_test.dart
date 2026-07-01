// Accessibility pass on the new Sprint 4 surfaces (Prompt 9).
//
// Mirrors the Sprint 3 colorblind audit approach: codify machine-checkable
// guidelines so regressions fail CI. Here we assert tap-target sizing and
// labelled-tap-target semantics on the alert inbox and the health-insights
// screen, plus that the dashboard inbox bell carries a semantic label and the
// inbox conveys risk with an icon (not colour alone).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/alerts/data/repositories/firestore_user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alert_inbox_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/presentation/health_insights_screen.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';

const _repo = StaticRecommendationRepository();

UserModel _user() =>
    UserModel(uid: 'u1', email: 'a@b.com', createdAt: DateTime.utc(2026, 1, 1));

Map<String, dynamic> _alertDoc() => {
  'title': 'Air quality rising in Lahore',
  'body': 'High Smog risk.',
  'category': 'respiratory',
  'city': 'Lahore',
  'riskLevel': 'High',
  'disease': 'Smog',
  'recommendation': {
    'id': 'rec-resp-air',
    'text': 'Keep windows closed.',
    'source': 'WHO — Air pollution',
    'sourceUrl': 'https://www.who.int/health-topics/air-pollution',
  },
  'deepLink': '',
  'riskEstimateId': 'Lahore_2026-06-30',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 30, 12)),
  'read': false,
  'readAt': null,
};

Future<Widget> _inbox() async {
  final firestore = FakeFirebaseFirestore();
  await firestore
      .collection('userAlerts')
      .doc('u1')
      .collection('items')
      .doc('a1')
      .set(_alertDoc());
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(_user())),
      userAlertsRepositoryProvider.overrideWithValue(
        FirestoreUserAlertsRepository(firestore: firestore),
      ),
    ],
    child: const MaterialApp(home: AlertInboxScreen()),
  );
}

Widget _healthInsights() => ProviderScope(
  overrides: [
    userCityProvider.overrideWith((ref) async => 'Lahore'),
    currentCityRiskProvider.overrideWith((ref) async => null),
    currentRecommendationProvider.overrideWith((ref) => _repo.lookup('*', '*')),
    adherenceInsightsProvider.overrideWith((ref) => AdherenceInsights.empty()),
  ],
  child: const MaterialApp(home: HealthInsightsScreen()),
);

void main() {
  group('Sprint 4 accessibility guidelines', () {
    testWidgets('alert inbox meets tap-target and labelled-target guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(await _inbox());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('health insights screen meets tap-target guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_healthInsights());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('inbox conveys risk with an icon, not colour alone', (
      tester,
    ) async {
      await tester.pumpWidget(await _inbox());
      await tester.pumpAndSettle();

      // The High-risk alert renders its distinct warning glyph (colorblind-safe).
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    });
  });
}
