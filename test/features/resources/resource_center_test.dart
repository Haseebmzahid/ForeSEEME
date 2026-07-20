import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/core/services/share_service.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_center_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/featured_article_card.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_article_card.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

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

/// Records the last shared text instead of opening a real share sheet.
class FakeShareService implements ShareService {
  String? sharedText;
  String? sharedSubject;

  @override
  Future<void> shareText(String text, {String? subject}) async {
    sharedText = text;
    sharedSubject = subject;
  }
}

/// Builds a router mirroring the app's `/resources` + nested article route,
/// so navigation (push to article, pop back) exercises real GoRouter behaviour
/// rather than a mocked callback.
GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/resources',
    routes: [
      GoRoute(
        path: '/resources',
        builder: (context, state) => const ResourceCenterScreen(),
        routes: [
          GoRoute(
            path: 'article/:articleId',
            builder: (context, state) =>
                ArticleScreen(articleId: state.pathParameters['articleId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/nearby-hospitals',
        builder: (context, state) => const Scaffold(body: Text('Hospitals')),
      ),
    ],
  );
}

// `flutter_riverpod` 3.3.1 does not export the `Override` type, so this list
// is left un-annotated (`List<dynamic>`) rather than naming a nonexistent
// type — mirrors test/integration/pipeline_e2e_test.dart's documented
// workaround for the same gap.
Future<FakeLauncherService> pumpCenter(
  WidgetTester tester, {
  List<dynamic> extraOverrides = const [],
}) async {
  final launcher = FakeLauncherService();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // A tall viewport so the whole (lazy) list renders for assertions.
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        launcherServiceProvider.overrideWithValue(launcher),
        articleBookmarkStoreProvider.overrideWithValue(
          ArticleBookmarkStore(prefs),
        ),
        ...extraOverrides,
      ],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
  return launcher;
}

/// The list-row card for [title] — scoped to [ResourceArticleCard] (not the
/// separate [FeaturedArticleCard]) so it stays unambiguous even when a title
/// is legitimately shown twice (once featured, once in the list).
Finder _listCardFor(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(ResourceArticleCard),
);

void main() {
  group('content rendering', () {
    testWidgets('renders the centre, emergency card, and featured guide', (
      tester,
    ) async {
      await pumpCenter(tester);

      expect(find.text('Resource Center'), findsOneWidget);
      expect(find.text('Emergency · Rescue 1122'), findsOneWidget);
      expect(find.byType(FeaturedArticleCard), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Lungs'), findsWidgets);

      // Guides + their visible source citations and reading time. The default
      // (no risk data) topic order features an air-quality guide, so its title
      // legitimately appears twice — once in the hero card, once in the list.
      expect(_listCardFor('Protecting your lungs on smog days'), findsOneWidget);
      expect(
        find.text('When to stay indoors (Air Quality Index)'),
        findsWidgets,
      );
      expect(find.textContaining('Source:'), findsWidgets);
      expect(find.textContaining('verified'), findsWidgets);
      expect(find.textContaining('min ·'), findsWidgets);
    });

    testWidgets('category chip filters the guide list', (tester) async {
      await pumpCenter(tester);

      await tester.tap(find.text('Heat'));
      await tester.pumpAndSettle();

      expect(find.text('Staying safe in extreme heat'), findsOneWidget);
      expect(find.text('Protecting your lungs on smog days'), findsNothing);
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

  group('article navigation', () {
    testWidgets('opening a guide pushes the routed article screen', (
      tester,
    ) async {
      final launcher = await pumpCenter(tester);

      await tester.tap(_listCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleScreen), findsOneWidget);
      expect(
        find.textContaining('Source: World Health Organization'),
        findsWidgets,
      );
      expect(find.textContaining('min read'), findsOneWidget);

      await tester.tap(find.text('View source'));
      await tester.pump();
      expect(
        launcher.openedUrl,
        'https://www.who.int/health-topics/air-pollution',
      );

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceCenterScreen), findsOneWidget);
    });

    testWidgets('bookmarking an article persists and shows on its card', (
      tester,
    ) async {
      await pumpCenter(tester);

      await tester.tap(_listCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_rounded), findsWidgets);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // The card behind it now shows the bookmarked indicator.
      expect(
        find
            .descendant(
              of: _listCardFor('Protecting your lungs on smog days'),
              matching: find.byIcon(Icons.bookmark_rounded),
            )
            .evaluate(),
        isNotEmpty,
      );
    });

    testWidgets('sharing an article hands the platform sheet its title, '
        'summary and cited source', (tester) async {
      final share = FakeShareService();
      await pumpCenter(
        tester,
        extraOverrides: [shareServiceProvider.overrideWithValue(share)],
      );

      await tester.tap(_listCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share_rounded));
      await tester.pump();

      expect(
        share.sharedText,
        contains('Protecting your lungs on smog days'),
      );
      expect(share.sharedText, contains('World Health Organization'));
      expect(share.sharedText, contains('https://www.who.int'));
      expect(share.sharedSubject, 'Protecting your lungs on smog days');
    });
  });

  group('context-aware ordering', () {
    testWidgets(
      'an elevated air-quality driver features an air-quality-topic guide '
      'and labels it as prioritized',
      (tester) async {
        final generatedAt = DateTime.utc(2026, 6, 28);
        await pumpCenter(
          tester,
          extraOverrides: [
            userCityProvider.overrideWith((ref) => 'Lahore'),
            riskRepositoryProvider.overrideWithValue(
              FakeRiskRepository(
                seed: {
                  'Lahore': RiskEstimateModel(
                    city: 'Lahore',
                    riskLevel: RiskLevel.high,
                    disease: 'Dengue',
                    confidence: 0.9,
                    temperature: 30.0,
                    humidity: 50.0,
                    aqi: 250.0,
                    generatedAt: generatedAt,
                    modelVersion: 'stub-0.0.0',
                  ),
                },
              ),
            ),
          ],
        );

        expect(find.text('PRIORITIZED FOR TODAY'), findsOneWidget);
        // Featured (hero) + listed — both legitimately show the same guide.
        expect(
          find.text('When to stay indoors (Air Quality Index)'),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'no elevated risk signal shows the calm default feature label',
      (tester) async {
        await pumpCenter(
          tester,
          extraOverrides: [userCityProvider.overrideWith((ref) => null)],
        );

        expect(find.text("EDITOR'S PICK"), findsOneWidget);
      },
    );
  });

  group('content integrity (no unsourced claims)', () {
    test(
      'every article has a name, an https source URL, real reading content, '
      'and is verified',
      () {
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
          expect(a.content, isNotEmpty, reason: '${a.id} has no content');
          expect(
            a.readingMinutes,
            greaterThanOrEqualTo(1),
            reason: '${a.id} reading time not computed',
          );
        }
        expect(repo.emergencyContact().number, '1122');
      },
    );
  });
}
