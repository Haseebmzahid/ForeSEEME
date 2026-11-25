import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/disclaimer_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

class _Launcher implements LauncherService {
  String? dialed;

  @override
  Future<bool> dialPhone(String number) async {
    dialed = number;
    return false;
  }

  @override
  Future<bool> openExternalUrl(String url) async => false;
}

void main() {
  for (final signedIn in [false, true]) {
    testWidgets(
      'public emergency and directory work with signedIn=$signedIn',
      (tester) async {
        final account = signedIn
            ? UserModel(
                uid: 'pending',
                email: 'pending@example.test',
                createdAt: DateTime.utc(2026),
              )
            : null;
        final launcher = _Launcher();
        var privateReads = 0;
        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWithValue(AsyncData(account)),
            healthProfileRepositoryProvider.overrideWith(
              (_) {
                privateReads++;
                throw StateError('Public emergency view accessed a profile');
              },
            ),
            currentCityRiskProvider.overrideWith(
              (_) {
                privateReads++;
                throw StateError('Public emergency view accessed personal risk');
              },
            ),
            launcherServiceProvider.overrideWithValue(launcher),
            publicNearbyHospitalsProvider.overrideWith(
              (_) async => NearbyHospitalsResult(
                hospitals: [],
                fetchedAt: DateTime.utc(2026),
                servedFromCache: false,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(appRouterProvider);
        addTearDown(router.dispose);
        router.go('/emergency');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('ForeSeeMe is not an emergency service'),
          findsOneWidget,
        );
        await tester.tap(find.text('Call 1122'));
        await tester.pump();
        expect(launcher.dialed, '1122');
        expect(
          find.textContaining('Could not open the dialer'),
          findsOneWidget,
        );
        await tester.tap(find.text('Nearby hospitals and clinics'));
        await tester.pumpAndSettle();
        expect(find.text('Nearby Care'), findsOneWidget);
        expect(find.text('No hospitals found nearby'), findsOneWidget);
        final context = tester.element(find.text('Nearby Care'));
        final mapLink = await router.routeInformationParser
            .parseRouteInformationWithDependencies(
              RouteInformation(uri: Uri.parse('/emergency/nearby/map')),
              context,
            );
        expect(mapLink.uri.path, '/emergency/nearby');
        for (final path in [
          '/home',
          '/resources',
          '/resources/saved',
          '/nearby-hospitals',
        ]) {
          final match = await router.routeInformationParser
              .parseRouteInformationWithDependencies(
                RouteInformation(uri: Uri.parse(path)),
                context,
              );
          expect(match.uri.path, signedIn ? '/verify-email' : '/login');
        }
        expect(privateReads, 0);
      },
    );
  }

  testWidgets(
    'verified users still need the disclaimer for Saved Articles',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWithValue(
            AsyncData(
              UserModel(
                uid: 'verified',
                email: 'verified@example.test',
                emailVerified: true,
                createdAt: DateTime.utc(2026),
              ),
            ),
          ),
          profileExistsProvider.overrideWithValue(const AsyncData(true)),
          disclaimerAcceptedProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        const MaterialApp(home: Text('route fixture')),
      );
      final match = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri.parse('/resources/saved')),
            tester.element(find.text('route fixture')),
          );
      expect(match.uri.path, '/health-disclaimer');
    },
  );
}
