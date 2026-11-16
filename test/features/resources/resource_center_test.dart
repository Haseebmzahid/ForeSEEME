import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/core/services/share_service.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_center_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_chrome.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_sheets.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';
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
  tester.view.physicalSize = const Size(800, 3600);
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
        // Sprint M8.3: the default `resourceRepositoryProvider` now performs a
        // real Firestore read; pin it to the deterministic static fixture so
        // these tests stay fast, offline, and independent of seed state.
        resourceRepositoryProvider.overrideWithValue(
          const StaticResourceRepository(),
        ),
        ...extraOverrides,
      ],
      child: MaterialApp.router(
        routerConfig: _buildRouter(),
        // The knowledge field runs a free-running `Ticker` for its orbits,
        // drift and breathing, which would make `pumpAndSettle` time out
        // forever. Reduced motion is the honest switch for that: the field
        // still composes, it just holds its opening frame — and the same flag
        // collapses the card-lift-then-open gesture to an immediate open, so
        // navigation assertions do not depend on a timer.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return launcher;
}

/// The grid card for [title] — scoped to [RcResourceCard], since a title also
/// appears on the contextual rail and in the full catalogue.
Finder _gridCardFor(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(RcResourceCard),
);

/// The category rail's dot for [label]. The same word is printed on every card
/// filed under it, so an unscoped `find.text(...).first` can land on a card —
/// and open an article instead of filtering.
Finder _categoryDot(String label) => find.descendant(
  of: find.byType(RcCategoryRail),
  matching: find.text(label),
);

/// The search layer's card for [title] — the screen behind it stays in the
/// tree (the layer is a non-opaque route), so a bare text finder would also
/// match the grid and catalogue underneath.
Finder _searchResultFor(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(RcSearchResultCard),
);

NearbyHospitalsResult _hospitals() => NearbyHospitalsResult(
  hospitals: [
    const Hospital(
      id: 'h1',
      name: 'Jinnah Hospital',
      address: '1 Ring Rd',
      latitude: 31.5,
      longitude: 74.3,
      distanceKm: 2.4,
      phoneNumber: '+924299231400',
      openNow: true,
    ),
    const Hospital(
      id: 'h2',
      name: 'Services Hospital',
      address: '2 Jail Rd',
      latitude: 31.54,
      longitude: 74.33,
      distanceKm: 3.1,
    ),
  ],
  fetchedAt: DateTime.now(),
  servedFromCache: false,
);

void main() {
  group('content rendering', () {
    testWidgets('renders the field, its live read, and the catalogue', (
      tester,
    ) async {
      await pumpCenter(tester);

      expect(find.text('FORESEEME · RESOURCE CENTER'), findsOneWidget);
      expect(
        find.text("Knowledge for what's happening around you."),
        findsOneWidget,
      );
      // No risk estimate in this host: the field says so rather than implying
      // a reading it does not have.
      expect(find.text('NO ENVIRONMENTAL SIGNAL'), findsOneWidget);
      expect(find.text('BALANCED WEIGHTING'), findsOneWidget);

      expect(find.text('Need help now?'), findsOneWidget);
      expect(find.text('EXPLORE HEALTH KNOWLEDGE'), findsOneWidget);
      expect(find.text('CARE NEAR YOU'), findsOneWidget);
      expect(find.text('FULL CATALOGUE'), findsOneWidget);

      // The category rail carries exactly the topics the app stores.
      for (final label in [
        'ALL',
        'AIR QUALITY',
        'LUNGS',
        'ASTHMA',
        'HEAT',
        'HEART',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing $label');
      }

      // ALL is the whole verified catalogue, derived — never hard-coded.
      expect(find.text('14 / 14'), findsOneWidget);
      expect(_gridCardFor('Protecting your lungs on smog days'), findsOneWidget);

      // Every card's meta line carries the real reading time and cited source.
      expect(find.textContaining('MIN · WHO'), findsWidgets);
      expect(
        find.text(
          '14 VERIFIED GUIDES · EVERY ENTRY CITES A PUBLIC-HEALTH AUTHORITY.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the category rail filters the field and updates the count', (
      tester,
    ) async {
      await pumpCenter(tester);

      await tester.tap(_categoryDot('HEAT'));
      await tester.pumpAndSettle();

      expect(find.text('3 / 14'), findsOneWidget);
      expect(_gridCardFor('Staying safe in extreme heat'), findsOneWidget);
      expect(_gridCardFor('Protecting your lungs on smog days'), findsNothing);
    });
  });

  group('loading', () {
    testWidgets('the field assembles behind shimmering slabs', (tester) async {
      final gate = Completer<List<ResourceArticle>>();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            articleBookmarkStoreProvider.overrideWithValue(
              ArticleBookmarkStore(prefs),
            ),
            resourceArticlesAsyncProvider.overrideWith((ref) => gate.future),
          ],
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ASSEMBLING KNOWLEDGE FIELD'), findsOneWidget);
      expect(find.text('EXPLORE HEALTH KNOWLEDGE'), findsNothing);

      gate.complete(await const StaticResourceRepository().articles());
      await tester.pumpAndSettle();

      expect(find.text('ASSEMBLING KNOWLEDGE FIELD'), findsNothing);
      expect(find.text('14 / 14'), findsOneWidget);
    });
  });

  // The acceptance criteria for the production catalogue: every category the
  // rail offers must return real, trusted resources — and every count must be
  // derived from the catalogue, never written into the UI.
  group('production catalogue', () {
    test('every entry is publisher-attributed and externally linked', () async {
      final articles = await const StaticResourceRepository().articles();

      expect(articles, isNotEmpty);
      for (final a in articles) {
        expect(a.sourceUrl, startsWith('https://'), reason: a.id);
        expect(a.sourceName.trim(), isNotEmpty, reason: a.id);
        expect(a.categories, isNotEmpty, reason: a.id);
        expect(a.categories, contains(a.topic), reason: a.id);
        // The badge is earned, never assumed.
        expect(
          a.isTrustedSource,
          a.verified && a.authority.isTrusted,
          reason: a.id,
        );
        // A verification date may be absent, but never a future one, and it is
        // never silently reused as a publication date.
        final verified = a.lastVerifiedAt;
        if (verified != null) {
          expect(verified.isAfter(DateTime.now().toUtc()), isFalse, reason: a.id);
        }
        if (a.publishedAt != null && verified != null) {
          expect(a.publishedAt, isNot(equals(verified)), reason: a.id);
        }
      }
    });

    test('WHO fact sheets carry the publisher own publication date', () async {
      final articles = await const StaticResourceRepository().articles();
      final factSheets = articles.where((a) => a.id.startsWith('who-'));

      expect(factSheets, hasLength(6));
      for (final a in factSheets) {
        expect(a.authority, ResourceAuthority.who, reason: a.id);
        expect(a.publishedAt, isNotNull, reason: a.id);
        expect(a.sourceUrl, contains('who.int'), reason: a.id);
      }
    });

    testWidgets('each category filter returns real resources', (tester) async {
      await pumpCenter(tester);

      // Derived from the catalogue itself, so this stays honest if it grows.
      final articles = await const StaticResourceRepository().articles();
      int countFor(ResourceTopic t) =>
          articles.where((a) => a.categories.contains(t)).length;

      const labels = {
        ResourceTopic.asthma: 'ASTHMA',
        ResourceTopic.lungs: 'LUNGS',
        ResourceTopic.heart: 'HEART',
        ResourceTopic.airQuality: 'AIR QUALITY',
        ResourceTopic.heat: 'HEAT',
      };

      for (final entry in labels.entries) {
        final expected = countFor(entry.key);
        expect(
          expected,
          greaterThan(0),
          reason: '${entry.value} has no resources in the catalogue',
        );

        await tester.tap(_categoryDot(entry.value));
        await tester.pumpAndSettle();

        expect(
          find.text('$expected / ${articles.length}'),
          findsOneWidget,
          reason: '${entry.value} count is not derived from the catalogue',
        );
        expect(
          find.text('Nothing matches this view.'),
          findsNothing,
          reason: '${entry.value} fell through to the empty state',
        );
        expect(find.byType(RcResourceCard), findsNWidgets(expected));
      }
    });

    testWidgets('ASTHMA surfaces the WHO asthma fact sheet', (tester) async {
      await pumpCenter(tester);

      await tester.tap(_categoryDot('ASTHMA'));
      await tester.pumpAndSettle();

      expect(_gridCardFor('Asthma'), findsOneWidget);
      expect(find.text('3 / 14'), findsOneWidget);
    });

    testWidgets('HEART surfaces cardiovascular guidance and links out', (
      tester,
    ) async {
      final launcher = await pumpCenter(tester);

      await tester.tap(_categoryDot('HEART'));
      await tester.pumpAndSettle();

      expect(_gridCardFor('Cardiovascular diseases (CVDs)'), findsOneWidget);

      await tester.tap(_gridCardFor('Cardiovascular diseases (CVDs)'));
      await tester.pumpAndSettle();

      // Publisher date and verification date are shown, and distinctly.
      expect(find.textContaining('Published 31 Jul 2025'), findsOneWidget);
      expect(find.textContaining('Verified 20 Aug 2026'), findsOneWidget);

      await tester.tap(find.text('Read full guidance at WHO'));
      await tester.pumpAndSettle();

      expect(
        launcher.openedUrl,
        'https://www.who.int/news-room/fact-sheets/detail/'
        'cardiovascular-diseases-(cvds)',
      );
    });

    testWidgets('search reaches the catalogue by publisher and by category', (
      tester,
    ) async {
      await pumpCenter(tester);

      await tester.tap(find.text('Search verified guidance'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'cardiovascular');
      await tester.pumpAndSettle();
      expect(
        _searchResultFor('Cardiovascular diseases (CVDs)'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches this view.'), findsOneWidget);
    });
  });

  group('emergency', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('emergency effective text is undecorated at scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        var care = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 24, bottom: 24),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showRcEmergencySheet(
                    context: context,
                    theme: ResourceCenterTheme.of(context),
                    contactName: 'Rescue 1122',
                    contactDescription:
                        'Punjab Emergency Service · Ambulance & Rescue',
                    onCall: () => calls++,
                    onFindCare: () => care++,
                  ),
                  child: const Text('Open emergency'),
                ),
              ),
            ),
          ),
        );
        Future<void> open() async {
          await tester.tap(find.text('Open emergency'));
          await tester.pumpAndSettle();
        }

        await open();
        final shell = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_RcSheetShell',
        );
        expect(shell, findsOneWidget);
        final paragraphs = tester.widgetList<RichText>(
          find.descendant(of: shell, matching: find.byType(RichText)),
        );
        expect(paragraphs.length, greaterThanOrEqualTo(7));
        for (final paragraph in paragraphs) {
          // RichText receives the actual DefaultTextStyle + Text.style merge.
          expect(
            paragraph.text.style?.decoration,
            TextDecoration.none,
            reason: paragraph.text.toPlainText(),
          );
        }
        expect(find.text('Need help now?'), findsOneWidget);
        expect(
          find.textContaining('does not assess your condition'),
          findsOneWidget,
        );
        final disclaimer = find.textContaining(
          'FORESEEME DOES NOT ROUTE EMERGENCY CALLS.',
        );
        await tester.ensureVisible(disclaimer);
        await tester.pumpAndSettle();
        expect(disclaimer.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(disclaimer).dy, lessThanOrEqualTo(616));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Call Rescue 1122'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Call Rescue 1122'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        await open();
        await tester.ensureVisible(find.text('FIND NEAREST CARE'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('FIND NEAREST CARE'));
        await tester.pumpAndSettle();
        expect(care, 1);
        expect(tester.takeException(), isNull);
      });
    }


    testWidgets('the banner opens the sheet, which dials the real contact', (
      tester,
    ) async {
      final launcher = await pumpCenter(tester);

      await tester.tap(find.text('Need help now?'));
      await tester.pumpAndSettle();

      expect(find.text('IMMEDIATE HELP'), findsOneWidget);
      expect(
        find.text(
          'ForeSeeMe is not an emergency service and does not assess your '
          'condition.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Call Rescue 1122'));
      await tester.pumpAndSettle();

      expect(launcher.dialedNumber, '1122');
    });

    testWidgets('the sheet routes escalation to the real care directory', (
      tester,
    ) async {
      await pumpCenter(tester);

      await tester.tap(find.text('Need help now?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FIND NEAREST CARE'));
      await tester.pumpAndSettle();

      expect(find.text('Hospitals'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('the search layer filters the field and opens a result', (
      tester,
    ) async {
      await pumpCenter(tester);

      await tester.tap(find.text('Search verified guidance'));
      await tester.pumpAndSettle();

      expect(find.text('FULL FIELD'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'heat');
      await tester.pumpAndSettle();

      // The count in the label must agree with the list it heads — asserting a
      // fixed number here would just re-encode the catalogue's current size.
      final matches = tester.widgetList(find.byType(RcSearchResultCard)).length;
      expect(matches, greaterThan(0));
      expect(find.text('$matches MATCHES IN FIELD'), findsOneWidget);
      expect(_searchResultFor('Staying safe in extreme heat'), findsOneWidget);
      expect(_searchResultFor('Heat and health'), findsOneWidget);
      expect(
        _searchResultFor('Protecting your lungs on smog days'),
        findsNothing,
      );

      await tester.tap(_searchResultFor('Staying safe in extreme heat'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleScreen), findsOneWidget);
    });

    testWidgets('a query with no match offers the way back to the full field', (
      tester,
    ) async {
      await pumpCenter(tester);

      await tester.tap(find.text('Search verified guidance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches this view.'), findsOneWidget);
      await tester.tap(find.text('EXPLORE ALL GUIDANCE'));
      await tester.pumpAndSettle();
      expect(find.text('FULL FIELD'), findsOneWidget);
    });
  });

  group('article navigation', () {
    testWidgets('opening a guide pushes the routed article screen', (
      tester,
    ) async {
      final launcher = await pumpCenter(tester);

      await tester.tap(_gridCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleScreen), findsOneWidget);
      expect(
        find.textContaining('WHO · VERIFIED SOURCE'),
        findsOneWidget,
      );
      expect(find.textContaining('MIN READ'), findsOneWidget);
      expect(find.text('World Health Organization (WHO)'), findsOneWidget);

      await tester.tap(find.text('Read full guidance at WHO'));
      await tester.pumpAndSettle();
      expect(
        launcher.openedUrl,
        'https://www.who.int/health-topics/air-pollution',
      );

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceCenterScreen), findsOneWidget);
    });

    testWidgets('the full catalogue opens a guide too', (tester) async {
      await pumpCenter(tester);

      await tester.tap(find.byType(RcCatalogueRow).first);
      await tester.pumpAndSettle();

      expect(find.byType(ArticleScreen), findsOneWidget);
    });

    testWidgets('bookmarking an article persists across a pop', (tester) async {
      await pumpCenter(tester);

      await tester.tap(_gridCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      await tester.tap(_gridCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    });

    testWidgets('sharing an article hands the platform sheet its title, '
        'summary and cited source', (tester) async {
      final share = FakeShareService();
      await pumpCenter(
        tester,
        extraOverrides: [shareServiceProvider.overrideWithValue(share)],
      );

      await tester.tap(_gridCardFor('Protecting your lungs on smog days'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share_rounded));
      await tester.pumpAndSettle();

      expect(share.sharedText, contains('Protecting your lungs on smog days'));
      expect(share.sharedText, contains('World Health Organization (WHO)'));
      expect(share.sharedText, contains('https://www.who.int'));
      expect(share.sharedSubject, 'Protecting your lungs on smog days');
    });
  });

  group('care near you', () {
    testWidgets('the Places lookup is not made until the user asks', (
      tester,
    ) async {
      var requested = false;
      await pumpCenter(
        tester,
        extraOverrides: [
          nearbyHospitalsProvider.overrideWith((ref) async {
            requested = true;
            return _hospitals();
          }),
        ],
      );

      expect(find.text('Find care near you'), findsOneWidget);
      expect(
        requested,
        isFalse,
        reason: 'opening the Learn tab must not read the device location',
      );

      await tester.tap(find.text('FIND CARE NEAR ME'));
      await tester.pumpAndSettle();

      expect(requested, isTrue);
      expect(find.text('Jinnah Hospital'), findsOneWidget);
      expect(find.text('HOSPITAL · OPEN NOW'), findsOneWidget);
      // Places returned no hours for the second facility, so none are claimed.
      expect(find.text('HOSPITAL · HOURS UNKNOWN'), findsOneWidget);
      expect(find.text('2.4 km'), findsOneWidget);
    });

    testWidgets('selecting a facility opens its sheet and gets directions', (
      tester,
    ) async {
      final launcher = await pumpCenter(
        tester,
        extraOverrides: [
          nearbyHospitalsProvider.overrideWith((ref) async => _hospitals()),
        ],
      );

      await tester.tap(find.text('FIND CARE NEAR ME'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jinnah Hospital'));
      await tester.pumpAndSettle();

      expect(find.text('2.4 KM'), findsOneWidget);
      expect(find.text('STRAIGHT LINE'), findsOneWidget);

      await tester.tap(find.text('Get directions'));
      await tester.pumpAndSettle();

      expect(
        launcher.openedUrl,
        'https://www.google.com/maps/dir/?api=1&destination=31.5,74.3',
      );
    });

    testWidgets('a failed lookup hands off to the care directory', (
      tester,
    ) async {
      await pumpCenter(
        tester,
        extraOverrides: [
          nearbyHospitalsProvider.overrideWith(
            (ref) => Future<NearbyHospitalsResult>.error(Exception('denied')),
          ),
        ],
      );

      await tester.tap(find.text('FIND CARE NEAR ME'));
      await tester.pumpAndSettle();

      expect(find.text('No nearby facilities available'), findsOneWidget);
      await tester.tap(find.text('OPEN CARE DIRECTORY'));
      await tester.pumpAndSettle();
      expect(find.text('Hospitals'), findsOneWidget);
    });
  });

  group('context-aware field', () {
    testWidgets(
      'an elevated air-quality driver re-tints the field, names the driver '
      'and labels the rail',
      (tester) async {
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
                    generatedAt: DateTime.utc(2026, 6, 28),
                    modelVersion: 'stub-0.0.0',
                  ),
                },
              ),
            ),
          ],
        );

        expect(find.text('RELEVANT FOR YOU'), findsOneWidget);
        expect(find.text('PM2.5 250 · LAHORE'), findsOneWidget);
        expect(find.text('AIR QUALITY WEIGHTING'), findsOneWidget);
      },
    );

    testWidgets('no elevated signal keeps the calm rail heading', (
      tester,
    ) async {
      await pumpCenter(
        tester,
        extraOverrides: [userCityProvider.overrideWith((ref) => null)],
      );

      expect(find.text('EXPLORE'), findsOneWidget);
      expect(find.text('RELEVANT FOR YOU'), findsNothing);
    });
  });

  group('content integrity (no unsourced claims)', () {
    test(
      'every article has a name, an https source URL, real reading content, '
      'and is verified',
      () async {
        const repo = StaticResourceRepository();
        final articles = await repo.articles();

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
