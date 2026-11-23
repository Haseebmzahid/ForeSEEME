import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fyp_foreseeme/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/disease_explorer_entry.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/home_risk_field.dart';
import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/disclaimer_providers.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/comparison_screen.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/disease_explorer_screen.dart';
import 'fixtures.dart';

void main() {
  testWidgets(
    'Home entry follows risk and disclaimer and opens the existing destination',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
          GoRoute(
            path: '/disease-explorer',
            builder: (_, _) => const DiseaseExplorerScreen(),
          ),
          for (final path in [
            '/check-in',
            '/medications',
            '/health-insights',
            '/resources',
          ])
            GoRoute(
              path: path,
              builder: (_, _) => Scaffold(body: Text(path)),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWithValue(const AsyncData(null)),
            currentCityRiskProvider.overrideWith((ref) async => null),
            currentCityOverrideProvider.overrideWith((ref) => null),
            unreadAlertCountProvider.overrideWithValue(0),
            medicationsStreamProvider.overrideWithValue(const AsyncData([])),
            userCityProvider.overrideWithValue(const AsyncData('Lahore')),
            latestRiskForCityProvider.overrideWith(
              (ref, city) async => estimate(city: city),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Explore Disease Risks'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(HomeRiskField)).dy,
        lessThan(tester.getTopLeft(find.byType(MedicalDisclaimer)).dy),
      );
      expect(
        tester.getTopLeft(find.byType(MedicalDisclaimer)).dy,
        lessThan(tester.getTopLeft(find.byType(DiseaseExplorerEntry)).dy),
      );
      await tester.ensureVisible(find.text('Explore now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore now'));
      await tester.pumpAndSettle();
      expect(find.byType(DiseaseExplorerScreen), findsOneWidget);
      expect(
        GoRouterState.of(
          tester.element(find.byType(DiseaseExplorerScreen)),
        ).uri.path,
        '/disease-explorer',
      );
      router.pop();
      await tester.pumpAndSettle();
      for (final action in {
        'Check-In': '/check-in',
        'Medication': '/medications',
        'Insights': '/health-insights',
        'Learn': '/resources',
      }.entries) {
        await tester.ensureVisible(find.text(action.key));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action.key));
        await tester.pumpAndSettle();
        expect(
          GoRouterState.of(tester.element(find.text(action.value))).uri.path,
          action.value,
        );
        router.go('/home');
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final city in [null, 'Karachi']) {
    testWidgets('labelled Map action preserves city=$city', (tester) async {
      Uri? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                Scaffold(body: DiseaseExplorerMapAction(city: city)),
          ),
          GoRoute(
            path: '/disease-explorer',
            builder: (_, state) {
              opened = state.uri;
              return Scaffold(
                body: Text(state.uri.queryParameters['city'] ?? 'national'),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Disease Explorer'), findsOneWidget);
      await tester.tap(find.text('Disease Explorer'));
      await tester.pumpAndSettle();
      expect(opened?.path, '/disease-explorer');
      expect(opened?.queryParameters['city'], city);
      expect(find.text(city ?? 'national'), findsOneWidget);
    });
  }
  testWidgets(
    'actual router opens explorer independently and returns to Compare',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWithValue(
            AsyncData(
              UserModel(
                uid: 'test',
                email: 'test@example.com',
                createdAt: DateTime.utc(2026),
              ),
            ),
          ),
          profileExistsProvider.overrideWithValue(const AsyncData(true)),
          disclaimerAcceptedProvider.overrideWithValue(const AsyncData(true)),
          userCityProvider.overrideWith((ref) async => 'Lahore'),
          latestRiskForCityProvider.overrideWith(
            (ref, city) async => estimate(city: city),
          ),
          allCitiesRiskProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      router.go('/compare');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ComparisonScreen), findsOneWidget);
      router.push('/disease-explorer?city=Islamabad');
      await tester.pumpAndSettle();
      expect(find.byType(DiseaseExplorerScreen), findsOneWidget);
      expect(find.text('Islamabad'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ComparisonScreen), findsOneWidget);
      expect(find.byType(DiseaseExplorerScreen), findsNothing);
    },
  );
}
