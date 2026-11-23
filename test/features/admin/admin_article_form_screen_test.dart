import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/admin_api_client.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_article_form_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'fake_admin_api.dart';

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/admin/content',
    routes: [
      GoRoute(
        path: '/admin/content',
        builder: (context, state) => const Scaffold(body: Text('Content List')),
      ),
      GoRoute(
        path: '/admin/content/add',
        builder: (context, state) =>
            const Scaffold(body: AdminArticleFormScreen()),
      ),
      GoRoute(
        path: '/admin/content/edit',
        builder: (context, state) => Scaffold(
          body: AdminArticleFormScreen(
            article: state.extra as ResourceArticle?,
          ),
        ),
      ),
    ],
  );
}

// `flutter_riverpod` 3.3.1 does not export the `Override` type, so this list
// is left un-annotated (`List<dynamic>`) — mirrors
// test/features/resources/resource_center_test.dart's documented workaround.
Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String path, {
  List<dynamic> overrides = const [],
  Object? extra,
}) async {
  // A tall viewport so the whole (lazily-built) form ListView renders for
  // assertions — mirrors test/features/resources/resource_center_test.dart's
  // pumpCenter, which hit the same lazy-Sliver gotcha first.
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = _buildRouter();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isAdminProvider.overrideWith((ref) async => true),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  router.push(path, extra: extra);
  await tester.pumpAndSettle();
  return router;
}

const _baseOverrides = <dynamic>[];

void main() {
  Finder blockTextFieldAt(int index) =>
      find.byType(TextField).at(4 + index); // 0-3 are title/summary/source*

  group('validation', () {
    testWidgets('empty title blocks submit with a snackbar', (tester) async {
      await _pumpAt(tester, '/admin/content/add', overrides: _baseOverrides);

      await tester.enterText(blockTextFieldAt(0), 'Some body text');
      await tester.tap(find.text('Publish article'));
      await tester.pump();

      expect(find.text('Title is required.'), findsOneWidget);
    });

    testWidgets('a non-https source URL blocks submit', (tester) async {
      await _pumpAt(tester, '/admin/content/add', overrides: _baseOverrides);

      await tester.enterText(find.byKey(const Key('article-title-field')), 'T');
      await tester.enterText(
        find.byKey(const Key('article-summary-field')),
        'S',
      );
      await tester.enterText(
        find.byKey(const Key('article-source-name-field')),
        'WHO',
      );
      await tester.enterText(
        find.byKey(const Key('article-source-url-field')),
        'http://insecure.example',
      );
      await tester.enterText(blockTextFieldAt(0), 'Body');
      await tester.tap(find.text('Publish article'));
      await tester.pump();

      expect(find.text('Source URL must start with https://.'), findsOneWidget);
    });

    testWidgets('an all-empty block list blocks submit', (tester) async {
      await _pumpAt(tester, '/admin/content/add', overrides: _baseOverrides);

      await tester.enterText(find.byKey(const Key('article-title-field')), 'T');
      await tester.enterText(
        find.byKey(const Key('article-summary-field')),
        'S',
      );
      await tester.enterText(
        find.byKey(const Key('article-source-name-field')),
        'WHO',
      );
      await tester.enterText(
        find.byKey(const Key('article-source-url-field')),
        'https://who.int',
      );
      // Leave the single default block empty.
      await tester.tap(find.text('Publish article'));
      await tester.pump();

      expect(
        find.text('At least one content block is required.'),
        findsOneWidget,
      );
    });
  });

  group('create', () {
    testWidgets(
      'a valid submit saves the article with a title-derived slug id, logs '
      'the action, and pops back to the list',
      (tester) async {
        final api = FakeAdminApi();

        await _pumpAt(
          tester,
          '/admin/content/add',
          overrides: [adminApiClientProvider.overrideWithValue(api)],
        );

        await tester.enterText(
          find.byKey(const Key('article-title-field')),
          'Staying Safe In Extreme Heat',
        );
        await tester.enterText(
          find.byKey(const Key('article-summary-field')),
          'Reduce heat-illness risk.',
        );
        await tester.enterText(
          find.byKey(const Key('article-source-name-field')),
          'WHO',
        );
        await tester.enterText(
          find.byKey(const Key('article-source-url-field')),
          'https://www.who.int/health-topics/heatwaves',
        );
        await tester.enterText(blockTextFieldAt(0), 'Drink water regularly.');

        await tester.tap(find.text('Publish article'));
        await tester.pumpAndSettle();

        final (path, payload) = api.calls.single;
        expect(path, ['articles', 'staying-safe-in-extreme-heat']);
        expect(payload?['title'], 'Staying Safe In Extreme Heat');
        expect(payload?['content'], [
          {'kind': 'paragraph', 'text': 'Drink water regularly.'},
        ]);
        expect(payload?['create'], isTrue);

        // Popped back to the list on success.
        expect(find.text('Content List'), findsOneWidget);
      },
    );
  });

  group('edit', () {
    const existing = ResourceArticle(
      id: 'extreme-heat',
      title: 'Staying safe in extreme heat',
      summary: 'Reduce heat-illness risk during hot spells.',
      content: [
        ArticleBlock.heading('Through the day'),
        ArticleBlock.warning('Watch for heat exhaustion.'),
      ],
      sourceName: 'World Health Organization (WHO)',
      sourceUrl: 'https://www.who.int/health-topics/heatwaves',
      topic: ResourceTopic.heat,
    );

    testWidgets('prefills every field and both existing blocks', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        '/admin/content/edit',
        overrides: _baseOverrides,
        extra: existing,
      );

      expect(find.text('Staying safe in extreme heat'), findsOneWidget);
      expect(
        find.text('Reduce heat-illness risk during hot spells.'),
        findsOneWidget,
      );
      expect(find.text('Through the day'), findsOneWidget);
      expect(find.text('Watch for heat exhaustion.'), findsOneWidget);
      // The id stays fixed and is surfaced, not editable as a separate field.
      expect(find.textContaining('extreme-heat'), findsOneWidget);
    });

    testWidgets(
      'saving an edit keeps the original id even if the title changed, and '
      'logs an update (not a create)',
      (tester) async {
        final api = FakeAdminApi();

        await _pumpAt(
          tester,
          '/admin/content/edit',
          overrides: [adminApiClientProvider.overrideWithValue(api)],
          extra: existing,
        );

        await tester.enterText(
          find.byKey(const Key('article-title-field')),
          'Staying safe in EXTREME heat (updated)',
        );
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        final (path, payload) = api.calls.single;
        expect(path, ['articles', 'extreme-heat']);
        expect(payload?['title'], 'Staying safe in EXTREME heat (updated)');
        expect(payload?['create'], isFalse);
      },
    );
  });

  group('block editor', () {
    testWidgets('add block appends an empty paragraph row', (tester) async {
      await _pumpAt(tester, '/admin/content/add', overrides: _baseOverrides);

      expect(find.byType(TextField), findsNWidgets(5)); // 4 fields + 1 block
      await tester.tap(find.text('Add block'));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('the sole block cannot be removed, but a second one can', (
      tester,
    ) async {
      await _pumpAt(tester, '/admin/content/add', overrides: _baseOverrides);

      expect(find.byTooltip('Remove block'), findsNothing);

      await tester.tap(find.text('Add block'));
      await tester.pump();
      expect(find.byTooltip('Remove block'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Remove block').first);
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(5));
      expect(find.byTooltip('Remove block'), findsNothing);
    });
  });
}
