import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/widgets/offline_state.dart';

void main() {
  group('isOfflineError', () {
    test('classifies genuine connectivity signatures as offline', () {
      expect(
        isOfflineError(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(
        isOfflineError(Exception('[cloud_firestore/unavailable] backend')),
        isTrue,
      );
      expect(
        isOfflineError(Exception('[firebase_auth/network-request-failed]')),
        isTrue,
      );
      expect(isOfflineError(Exception('TimeoutException after 30s')), isTrue);
    });

    test('does NOT classify server / permission / generic errors as offline', () {
      expect(isOfflineError(Exception('permission-denied')), isFalse);
      expect(isOfflineError(Exception('boom')), isFalse);
      // A bare word "offline" alone is too weak a signal — must not match.
      expect(isOfflineError(Exception('offline')), isFalse);
    });
  });

  group('OfflineState', () {
    testWidgets('shows the offline headline + Retry, never a spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OfflineState(onRetry: () {})),
        ),
      );
      await tester.pump();

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Retry invokes the provided callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OfflineState(onRetry: () => taps++)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Retry'));
      expect(taps, 1);
    });

    testWidgets('settles under reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: OfflineState(onRetry: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Internet Connection'), findsOneWidget);
    });
  });
}
