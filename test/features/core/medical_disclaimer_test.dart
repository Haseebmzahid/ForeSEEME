import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/user_alerts_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alert_inbox_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_permission_screen.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/health_intelligence_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_details_screen.dart';

UserModel _signedInUser() =>
    UserModel(uid: 'u1', email: 'a@b.com', createdAt: DateTime.utc(2026, 1, 1));

/// Empty inbox repo so the alert inbox resolves to its (disclaimer-bearing)
/// empty state without Firebase.
class _EmptyAlertsRepository implements UserAlertsRepository {
  @override
  Future<UserAlertModel?> getAlertForPush(String uid, String pushId) async =>
      null;

  @override
  Stream<List<UserAlertModel>> watchAlerts(String uid) =>
      Stream.value(const []);

  @override
  Future<void> markRead(String uid, String alertId) async {}

  @override
  Future<void> markAllRead(String uid) async {}
}

void main() {
  group('MedicalDisclaimer component', () {
    testWidgets('banner shows the canonical non-diagnostic copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MedicalDisclaimer.banner())),
      );

      expect(find.text(MedicalDisclaimer.standardText), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });

    testWidgets('inline shows the short non-diagnostic copy', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MedicalDisclaimer.inline())),
      );

      expect(find.text(MedicalDisclaimer.shortText), findsOneWidget);
    });

    testWidgets('respects a message override', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MedicalDisclaimer.banner(message: 'Custom framing.'),
          ),
        ),
      );

      expect(find.text('Custom framing.'), findsOneWidget);
      expect(find.text(MedicalDisclaimer.standardText), findsNothing);
    });

    testWidgets('is read as one "Disclaimer:" group for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MedicalDisclaimer.banner())),
      );

      expect(find.bySemanticsLabel(RegExp(r'^Disclaimer:')), findsOneWidget);
      handle.dispose();
    });

    test('canonical copy states it is not a diagnosis and routes to help', () {
      final text = MedicalDisclaimer.standardText.toLowerCase();
      expect(text.contains('not a medical diagnosis'), isTrue);
      expect(text.contains('healthcare professional'), isTrue);
      expect(text.contains('emergency'), isTrue);
      // Never implies clinical diagnosis / prediction of disease.
      expect(text.contains('diagnose'), isFalse);
    });
  });

  group('renders on every risk-facing surface', () {
    // Signed-out override makes risk/insights providers short-circuit to their
    // safe empty/default states with no Firebase (userCityProvider → null).
    final signedOut = authStateProvider.overrideWith((ref) => Stream.value(null));

    testWidgets('onboarding / notification permission screen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NotificationPermissionScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MedicalDisclaimer), findsOneWidget);
    });

    testWidgets('health intelligence screen (risk + recommendations)', (
      tester,
    ) async {
      // Signed out: userCityProvider → null, so every risk provider
      // short-circuits to its safe empty state with no Firebase, and the
      // composed view resolves to its no-data form.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [signedOut],
          child: const MaterialApp(home: HealthIntelligenceScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MedicalDisclaimer), findsOneWidget);
    });

    testWidgets('risk details screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signedOut],
          child: const MaterialApp(home: RiskDetailsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The banner is pinned outside the async switcher, so it is present in
      // every data state.
      expect(find.byType(MedicalDisclaimer), findsOneWidget);
    });

    testWidgets('alert inbox screen (empty state still carries it)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_signedInUser()),
          ),
          userAlertsRepositoryProvider.overrideWithValue(
            _EmptyAlertsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AlertInboxScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No alerts yet'), findsOneWidget);
      expect(find.byType(MedicalDisclaimer), findsOneWidget);
    });
  });
}
