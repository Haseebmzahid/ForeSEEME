import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/features/admin/presentation/admin_content_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';

const _article1 = ResourceArticle(
  id: 'extreme-heat',
  title: 'Staying safe in extreme heat',
  summary: 'Reduce heat-illness risk during hot spells.',
  content: [ArticleBlock.paragraph('Drink water.')],
  sourceName: 'WHO',
  sourceUrl: 'https://www.who.int/',
  topic: ResourceTopic.heat,
);

const _article2 = ResourceArticle(
  id: 'lungs-smog',
  title: 'Protecting your lungs on smog days',
  summary: 'Cut exposure to fine particles.',
  content: [ArticleBlock.paragraph('Check AQI.')],
  sourceName: 'WHO',
  sourceUrl: 'https://www.who.int/',
  topic: ResourceTopic.lungs,
);

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/admin/content',
    routes: [
      GoRoute(
        // Scaffold-wrapped, matching how AdminShell hosts this screen in the
        // real app — AdminContentScreen has no Material/Scaffold of its own
        // by design (the shell supplies it), so InkWell needs it here too.
        path: '/admin/content',
        builder: (context, state) =>
            const Scaffold(body: AdminContentScreen()),
      ),
      GoRoute(
        path: '/admin/content/add',
        builder: (context, state) => const Scaffold(body: Text('Add Form')),
      ),
      GoRoute(
        path: '/admin/content/edit',
        builder: (context, state) => const Scaffold(body: Text('Edit Form')),
      ),
    ],
  );
}

// `flutter_riverpod` 3.3.1 does not export the `Override` type — see
// test/features/resources/resource_center_test.dart.
Future<void> _pump(WidgetTester tester, List<dynamic> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...overrides],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a non-admin sees the shared not-authorized view, not the list', (
    tester,
  ) async {
    await _pump(tester, [isAdminProvider.overrideWith((ref) async => false)]);

    expect(find.text('Not authorized'), findsOneWidget);
  });

  testWidgets('an admin sees an honest empty state before any article exists', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      resourceArticlesAsyncProvider.overrideWith((ref) async => const []),
    ]);

    expect(find.text('No articles yet'), findsOneWidget);
    expect(find.text('Add article'), findsOneWidget); // still offered
  });

  testWidgets('an admin sees every published article with its category', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      resourceArticlesAsyncProvider.overrideWith(
        (ref) async => const [_article1, _article2],
      ),
    ]);

    expect(find.text('Staying safe in extreme heat'), findsOneWidget);
    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('Protecting your lungs on smog days'), findsOneWidget);
    expect(find.text('Lungs'), findsOneWidget);
  });

  testWidgets('"Add article" navigates to the add route', (tester) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      resourceArticlesAsyncProvider.overrideWith((ref) async => const []),
    ]);

    await tester.tap(find.text('Add article'));
    await tester.pumpAndSettle();

    expect(find.text('Add Form'), findsOneWidget);
  });

  testWidgets('tapping an article navigates to the edit route with it as extra', (
    tester,
  ) async {
    await _pump(tester, [
      isAdminProvider.overrideWith((ref) async => true),
      resourceArticlesAsyncProvider.overrideWith((ref) async => const [_article1]),
    ]);

    await tester.tap(find.text('Staying safe in extreme heat'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Form'), findsOneWidget);
  });
}
