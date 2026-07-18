import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/medication/presentation/services/medication_deep_link_router.dart';
import 'package:fyp_foreseeme/features/medication/presentation/services/medication_notification_tap_handler.dart';

void main() {
  setUpAll(() {
    // MedicationNotificationTapHandler triggers a haptic on every tap; this
    // ensures platform channel calls resolve as no-ops rather than throwing
    // in a plain (non-widget) test.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // ── MedicationDeepLinkRouter (Phase 6) ─────────────────────────────────────
  group('MedicationDeepLinkRouter', () {
    test('action and recovery open Daily Check-In', () {
      expect(MedicationDeepLinkRouter.resolve('action'), '/check-in');
      expect(MedicationDeepLinkRouter.resolve('recovery'), '/check-in');
    });

    test('celebration, reflection, and coaching open the Adherence Journey', () {
      expect(MedicationDeepLinkRouter.resolve('celebration'), '/adherence-history');
      expect(MedicationDeepLinkRouter.resolve('reflection'), '/adherence-history');
      expect(MedicationDeepLinkRouter.resolve('coaching'), '/adherence-history');
    });

    test('never routes to the bare dashboard for a known category', () {
      for (final category in ['action', 'recovery', 'celebration', 'reflection', 'coaching']) {
        expect(MedicationDeepLinkRouter.resolve(category), isNot('/home'));
      }
    });

    test('null, empty, or unknown payloads fall back safely', () {
      expect(MedicationDeepLinkRouter.resolve(null), '/home');
      expect(MedicationDeepLinkRouter.resolve(''), '/home');
      expect(MedicationDeepLinkRouter.resolve('  '), '/home');
      expect(MedicationDeepLinkRouter.resolve('unknown_category'), '/home');
    });
  });

  // ── MedicationNotificationTapHandler (Phase 6, mirrors FcmMessageHandler) ─
  group('MedicationNotificationTapHandler', () {
    late StreamController<String> tapController;
    late List<String> navigated;
    late String? initialPayload;
    late MedicationNotificationTapHandler handler;

    MedicationNotificationTapHandler build() => MedicationNotificationTapHandler(
      tapStream: tapController.stream,
      consumeInitialPayload: () async => initialPayload,
      navigate: navigated.add,
    );

    setUp(() {
      tapController = StreamController<String>.broadcast();
      navigated = <String>[];
      initialPayload = null;
    });

    tearDown(() {
      handler.dispose();
      tapController.close();
    });

    test('a live tap navigates to the resolved route', () async {
      handler = build();
      await handler.start();

      tapController.add('action');
      await pumpEventQueue();

      expect(navigated, ['/check-in']);
    });

    test('a terminated-launch tap routes from the initial payload', () async {
      initialPayload = 'reflection';
      handler = build();

      await handler.start();

      expect(navigated, ['/adherence-history']);
    });

    test('no initial payload → no navigation on start', () async {
      handler = build();
      await handler.start();

      expect(navigated, isEmpty);
    });

    test('multiple live taps each navigate independently', () async {
      handler = build();
      await handler.start();

      tapController.add('celebration');
      await pumpEventQueue();
      tapController.add('coaching');
      await pumpEventQueue();

      expect(navigated, ['/adherence-history', '/adherence-history']);
    });

    test('an unrecognised payload still navigates, to the safe fallback', () async {
      handler = build();
      await handler.start();

      tapController.add('something_unexpected');
      await pumpEventQueue();

      expect(navigated, ['/home']);
    });

    test('calling start twice does not double-navigate a single tap', () async {
      handler = build();
      await handler.start();
      await handler.start(); // idempotent re-subscribe

      tapController.add('action');
      await pumpEventQueue();

      expect(navigated, ['/check-in']);
    });
  });
}
