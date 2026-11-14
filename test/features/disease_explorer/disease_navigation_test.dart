import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/comparison_screen.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/disease_explorer_screen.dart';
import 'fixtures.dart';

void main() {
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
          child: MaterialApp.router(routerConfig: router),
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
