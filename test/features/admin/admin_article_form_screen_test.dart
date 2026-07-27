import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_activity_log_repository.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_article_form_screen.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_content_repository.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';

class _FakeContentRepo implements ResourceContentRepository {
  final List<ResourceArticle> saved = [];

  @override
  Future<void> saveArticle(ResourceArticle article) async => saved.add(article);
}

class _FakeActivityLogRepo implements AdminActivityLogRepository {
  final List<AdminActivityLogEntry> entries = [];

  @override
  Future<void> append(AdminActivityLogEntry entry) async => entries.add(entry);

  @override
  Future<List<AdminActivityLogEntry>> recent({int limit = 100}) async => entries;
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/admin/content',
    routes: [
      GoRoute(
        path: '/admin/content',
        builder: (context, state) =>
            const Scaffold(body: Text('Content List')),
      ),
      GoRoute(
        path: '/admin/content/add',
        builder: (context, state) =>
            const Scaffold(body: AdminArticleFormScreen()),
      ),
      GoRoute(
        path: '/admin/content/edit',
        builder: (context, state) => Scaffold(
          body: AdminArticleFormScreen(article: state.extra as ResourceArticle?),
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
  // Only tests that override `authStateProvider` (and reach
  // AdminArticleFormController._logAction) need this — see the comment below.
  // Warming it up unconditionally would make the OTHER tests newly depend on
  // Firebase Auth just to build the screen, when today they never touch it.
  bool warmUpAuth = false,
}) async {
  // A tall viewport so the whole (lazily-built) form ListView renders for
  // assertions — mirrors test/features/resources/resource_center_test.dart's
  // pumpCenter, which hit the same lazy-Sliver gotcha first.
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = _buildRouter();

  if (warmUpAuth) {
    // Riverpod 3 StreamProvider gotcha (see the identical workaround in
    // test/features/admin/risk_override_test.dart's `ready()`): a
    // `Stream.value(...)`-backed override only delivers on a real event-loop
    // turn, so a synchronous `ref.read(authStateProvider).value` immediately
    // after first touching the provider can still see `null`. Building the
    // container explicitly lets us subscribe and wait for that turn before
    // the form is interacted with.
    //
    // Inside `testWidgets`, that wait MUST be `tester.pump(duration)`, not a
    // bare `Future.delayed`: `TestWidgetsFlutterBinding` runs on a virtual
    // clock that only advances when pumped, so an un-pumped `Future.delayed`
    // schedules a `Timer` that never fires and hangs the test forever
    // (`risk_override_test.dart`'s `ready()` gets away with a bare
    // `Future.delayed` only because it's a plain `test()`, outside that
    // binding). A widget must exist before the first `pump()`, so the empty
    // container is pumped once before the wait, then again with the delay.
    final container = ProviderContainer(overrides: [...overrides]);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
  } else {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

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
      await tester.enterText(find.byKey(const Key('article-summary-field')), 'S');
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
      await tester.enterText(find.byKey(const Key('article-summary-field')), 'S');
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
        final contentRepo = _FakeContentRepo();
        final activityLog = _FakeActivityLogRepo();

        await _pumpAt(
          tester,
          '/admin/content/add',
          warmUpAuth: true,
          overrides: [
            resourceContentRepositoryProvider.overrideWithValue(contentRepo),
            adminActivityLogRepositoryProvider.overrideWithValue(activityLog),
            authStateProvider.overrideWith(
              (ref) => Stream.value(
                UserModel(
                  uid: 'op-1',
                  email: 'op@example.com',
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ),
            ),
          ],
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

        expect(contentRepo.saved, hasLength(1));
        final saved = contentRepo.saved.single;
        expect(saved.id, 'staying-safe-in-extreme-heat');
        expect(saved.title, 'Staying Safe In Extreme Heat');
        expect(saved.content.single.text, 'Drink water regularly.');

        expect(activityLog.entries, hasLength(1));
        expect(activityLog.entries.single.action, 'article_create');
        expect(activityLog.entries.single.target, 'staying-safe-in-extreme-heat');

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

    testWidgets('prefills every field and both existing blocks', (tester) async {
      await _pumpAt(
        tester,
        '/admin/content/edit',
        overrides: _baseOverrides,
        extra: existing,
      );

      expect(
        find.text('Staying safe in extreme heat'),
        findsOneWidget,
      );
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
        final contentRepo = _FakeContentRepo();
        final activityLog = _FakeActivityLogRepo();

        await _pumpAt(
          tester,
          '/admin/content/edit',
          warmUpAuth: true,
          overrides: [
            resourceContentRepositoryProvider.overrideWithValue(contentRepo),
            adminActivityLogRepositoryProvider.overrideWithValue(activityLog),
            authStateProvider.overrideWith(
              (ref) => Stream.value(
                UserModel(
                  uid: 'op-1',
                  email: 'op@example.com',
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ),
            ),
          ],
          extra: existing,
        );

        await tester.enterText(
          find.byKey(const Key('article-title-field')),
          'Staying safe in EXTREME heat (updated)',
        );
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        expect(contentRepo.saved.single.id, 'extreme-heat'); // unchanged
        expect(
          contentRepo.saved.single.title,
          'Staying safe in EXTREME heat (updated)',
        );
        expect(activityLog.entries.single.action, 'article_update');
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
