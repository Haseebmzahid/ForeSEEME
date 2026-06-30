import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_center_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_article_card.dart';

/// Records launch intents instead of leaving the app (asserts the exact target).
class FakeLauncherService implements LauncherService {
  String? dialedNumber;
  String? openedUrl;

  @override
  Future<bool> dialPhone(String number) async {
    dialedNumber = number;
    return true;
  }

  @override
  Future<bool> openExternalUrl(String url) async {
    openedUrl = url;
    return true;
  }
}

Future<FakeLauncherService> pumpCenter(WidgetTester tester) async {
  final launcher = FakeLauncherService();
  // A tall viewport so the whole (lazy) list renders for assertions.
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [launcherServiceProvider.overrideWithValue(launcher)],
      child: const MaterialApp(home: ResourceCenterScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return launcher;
}

void main() {
  group('content rendering', () {
    testWidgets('renders the centre, emergency, and sourced guides', (
      tester,
    ) async {
      await pumpCenter(tester);

      expect(find.text('Resource Center'), findsOneWidget);
      expect(find.text('Emergency · Rescue 1122'), findsOneWidget);

      // Guides + their visible source citations.
      expect(find.text('Protecting your lungs on smog days'), findsOneWidget);
      expect(
        find.text('When to stay indoors (Air Quality Index)'),
        findsOneWidget,
      );
      expect(find.textContaining('Source:'), findsWidgets);
      expect(find.text('verified'), findsWidgets);
    });
  });

  group('emergency dial', () {
    testWidgets('tapping the emergency card dials tel:1122', (tester) async {
      final launcher = await pumpCenter(tester);

      await tester.tap(find.byType(EmergencyCard));
      await tester.pump();

      expect(launcher.dialedNumber, '1122');
    });
  });

  group('article source link', () {
    testWidgets('opening a guide exposes and launches its source URL', (
      tester,
    ) async {
      final launcher = await pumpCenter(tester);

      await tester.tap(find.byType(ResourceArticleCard).first);
      await tester.pumpAndSettle();

      // Citation visible in the detail sheet (also shown on the card behind it).
      expect(
        find.textContaining('Source: World Health Organization'),
        findsWidgets,
      );

      await tester.tap(find.text('View source'));
      await tester.pump();

      expect(
        launcher.openedUrl,
        'https://www.who.int/health-topics/air-pollution',
      );
    });
  });

  group('content integrity (no unsourced claims)', () {
    test('every article has a name, an https source URL, and is verified', () {
      const repo = StaticResourceRepository();
      final articles = repo.articles();

      expect(articles, isNotEmpty);
      for (final a in articles) {
        expect(
          a.sourceName.trim(),
          isNotEmpty,
          reason: '${a.id} has no source',
        );
        expect(
          a.sourceUrl,
          startsWith('https://'),
          reason: '${a.id} source URL not https',
        );
        expect(a.verified, isTrue, reason: '${a.id} not verified');
        expect(a.body, isNotEmpty, reason: '${a.id} has no body');
      }
      expect(repo.emergencyContact().number, '1122');
    });
  });
}
