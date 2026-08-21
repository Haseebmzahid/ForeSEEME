import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Back-stack behaviour of the app's secondary/detail routes.
///
/// The real `appRouterProvider` cannot be pumped in a unit test — its redirect
/// reads the live auth/profile providers and every branch builds a screen that
/// needs Firebase. So this mirrors the *route topology* of
/// `lib/core/routes/app_router.dart` (same shell branches, same nesting, same
/// paths) with stub screens, and asserts the stack semantics each real call
/// site depends on:
///
///   * `/medications/add`, `/medications/edit` and `/resources/article/:id` are
///     nested children — a `push()` keeps the launching screen underneath.
///   * `/adherence-history` is a *second* route inside the Medications branch,
///     not a child of `/medications`. `go()` there replaces the whole branch
///     stack and leaves nothing to pop back to, so system Back exits the app.
///     It must be pushed.
///
/// Bottom-nav tab roots (`/home`, `/check-in`, `/medications`, `/resources`,
/// `/profile`) are deliberately still reached with `go()` in the app; those are
/// branch switches, not stacked screens, and are not covered here.
void main() {
  late GlobalKey<NavigatorState> rootKey;
  late GlobalKey<NavigatorState> homeKey;
  late GlobalKey<NavigatorState> checkInKey;
  late GlobalKey<NavigatorState> medsKey;
  late GlobalKey<NavigatorState> resourcesKey;
  late GlobalKey<NavigatorState> profileKey;

  setUp(() {
    rootKey = GlobalKey<NavigatorState>();
    homeKey = GlobalKey<NavigatorState>(debugLabel: 'shellDashboard');
    checkInKey = GlobalKey<NavigatorState>(debugLabel: 'shellCheckIn');
    medsKey = GlobalKey<NavigatorState>(debugLabel: 'shellMeds');
    resourcesKey = GlobalKey<NavigatorState>(debugLabel: 'shellResources');
    profileKey = GlobalKey<NavigatorState>(debugLabel: 'shellProfile');
  });

  Widget stub(String label) => Scaffold(body: Center(child: Text(label)));

  GoRouter buildRouter(String initialLocation) {
    return GoRouter(
      navigatorKey: rootKey,
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/risk-map', builder: (_, _) => stub('RISK MAP')),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              navigatorKey: homeKey,
              routes: [GoRoute(path: '/home', builder: (_, _) => stub('HOME'))],
            ),
            StatefulShellBranch(
              navigatorKey: checkInKey,
              routes: [
                GoRoute(path: '/check-in', builder: (_, _) => stub('CHECK-IN')),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: medsKey,
              routes: [
                GoRoute(
                  path: '/medications',
                  builder: (_, _) => stub('MEDICATIONS'),
                  routes: [
                    GoRoute(
                      path: 'add',
                      // AddMedicationScreen's header/back control and its
                      // save/archive paths close the form with
                      // `Navigator.of(context).pop()` (it is also pumped
                      // bare, without a GoRouter, by the medication widget
                      // tests). Model that exactly.
                      builder: (context, _) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('ADD MEDICATION'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: '/adherence-history',
                  builder: (_, _) => stub('ADHERENCE HISTORY'),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: resourcesKey,
              routes: [
                GoRoute(
                  path: '/resources',
                  builder: (_, _) => stub('RESOURCE CENTER'),
                  routes: [
                    GoRoute(
                      path: 'article/:articleId',
                      builder: (_, state) =>
                          stub('ARTICLE ${state.pathParameters['articleId']}'),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: profileKey,
              routes: [
                GoRoute(path: '/profile', builder: (_, _) => stub('PROFILE')),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<GoRouter> pumpAt(WidgetTester tester, String location) async {
    final router = buildRouter(location);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  /// Delivers the platform `popRoute` message the Android system Back button
  /// sends, and reports whether the framework fell through to
  /// `SystemNavigator.pop()` — i.e. whether the app would have exited.
  Future<bool> pressSystemBack(WidgetTester tester) async {
    var exited = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exited = true;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
    return exited;
  }

  group('secondary screens preserve the launching screen', () {
    testWidgets('Home to Add Medication, Back returns to Home', (tester) async {
      final router = await pumpAt(tester, '/home');

      router.push('/medications/add');
      await tester.pumpAndSettle();
      expect(find.text('ADD MEDICATION'), findsOneWidget);
      expect(router.canPop(), isTrue);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('Medications to Add Medication, Back returns to Medications', (
      tester,
    ) async {
      final router = await pumpAt(tester, '/medications');

      router.push('/medications/add');
      await tester.pumpAndSettle();
      expect(find.text('ADD MEDICATION'), findsOneWidget);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('MEDICATIONS'), findsOneWidget);
    });

    testWidgets('Check-In to Add Medication, Back returns to Check-In', (
      tester,
    ) async {
      final router = await pumpAt(tester, '/check-in');

      router.push('/medications/add');
      await tester.pumpAndSettle();
      expect(find.text('ADD MEDICATION'), findsOneWidget);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('CHECK-IN'), findsOneWidget);
    });

    testWidgets('Risk Map to Check-In, Back returns to Risk Map', (
      tester,
    ) async {
      final router = await pumpAt(tester, '/risk-map');

      router.push('/check-in');
      await tester.pumpAndSettle();
      expect(find.text('CHECK-IN'), findsOneWidget);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('RISK MAP'), findsOneWidget);
    });

    testWidgets('Resource Center to Article, Back returns to Resource Center', (
      tester,
    ) async {
      final router = await pumpAt(tester, '/resources');

      router.push('/resources/article/asthma-101');
      await tester.pumpAndSettle();
      expect(find.text('ARTICLE asthma-101'), findsOneWidget);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('RESOURCE CENTER'), findsOneWidget);
    });
  });

  testWidgets(
    "the form's own back control agrees with system Back",
    (tester) async {
      final router = await pumpAt(tester, '/check-in');

      router.push('/medications/add');
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD MEDICATION'));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-IN'), findsOneWidget);
      expect(router.state.uri.toString(), '/check-in');
    },
  );

  group('the profile gate does not swallow a pushed health-profile edit', () {
    /// Mirrors the `isAuthenticated && hasProfile` arm of the real router's
    /// `redirect` (see `app_router.dart`), including the `isEditMode` guard.
    GoRouter buildGatedRouter({required bool hasProfile}) {
      return GoRouter(
        navigatorKey: rootKey,
        initialLocation: hasProfile ? '/profile' : '/health-profile',
        redirect: (context, state) {
          final location = state.matchedLocation;
          final isHealthProfileEdit =
              state.extra is Map && (state.extra! as Map)['isEditMode'] == true;
          if (!hasProfile) {
            return location == '/health-profile' ? null : '/health-profile';
          }
          if ((location == '/health-profile' && !isHealthProfileEdit) ||
              location == '/') {
            return '/home';
          }
          return null;
        },
        routes: [
          GoRoute(
            path: '/health-profile',
            builder: (_, state) => stub(
              state.extra is Map && (state.extra! as Map)['isEditMode'] == true
                  ? 'EDIT HEALTH PROFILE'
                  : 'HEALTH PROFILE SETUP',
            ),
          ),
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => Scaffold(body: shell),
            branches: [
              StatefulShellBranch(
                navigatorKey: homeKey,
                routes: [
                  GoRoute(path: '/home', builder: (_, _) => stub('HOME')),
                ],
              ),
              StatefulShellBranch(
                navigatorKey: profileKey,
                routes: [
                  GoRoute(path: '/profile', builder: (_, _) => stub('PROFILE')),
                ],
              ),
            ],
          ),
        ],
      );
    }

    testWidgets('Profile to Edit Health Profile, Back returns to Profile', (
      tester,
    ) async {
      final router = buildGatedRouter(hasProfile: true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.push('/health-profile', extra: {'isEditMode': true});
      await tester.pumpAndSettle();
      expect(find.text('EDIT HEALTH PROFILE'), findsOneWidget);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('PROFILE'), findsOneWidget);
    });

    testWidgets('a non-edit visit still redirects to Home', (tester) async {
      final router = buildGatedRouter(hasProfile: true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go('/health-profile');
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('the first-run gate is untouched', (tester) async {
      final router = buildGatedRouter(hasProfile: false);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go('/home');
      await tester.pumpAndSettle();

      expect(find.text('HEALTH PROFILE SETUP'), findsOneWidget);
    });
  });

  group('/adherence-history is a branch sibling, not a child', () {
    testWidgets('go() leaves nothing to pop back to (the regression)', (
      tester,
    ) async {
      final router = await pumpAt(tester, '/medications');

      router.go('/adherence-history');
      await tester.pumpAndSettle();

      expect(find.text('ADHERENCE HISTORY'), findsOneWidget);
      // This is the bug the fix removes: go() replaced the Medications branch
      // stack, so Back would have exited the app.
      expect(router.canPop(), isFalse);
      expect(await pressSystemBack(tester), isTrue);
    });

    testWidgets('push() keeps Medications underneath', (tester) async {
      final router = await pumpAt(tester, '/medications');

      router.push('/adherence-history');
      await tester.pumpAndSettle();
      expect(find.text('ADHERENCE HISTORY'), findsOneWidget);
      expect(router.canPop(), isTrue);

      expect(await pressSystemBack(tester), isFalse, reason: 'must not exit');
      expect(find.text('MEDICATIONS'), findsOneWidget);
    });
  });
}
