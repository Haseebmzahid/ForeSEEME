import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/routes/app_router.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fyp_foreseeme/features/health_profile/data/repositories/firestore_disclaimer_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/disclaimer_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/disclaimer_acceptance_screen.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/disclaimer_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';

class _FailingRepository implements DisclaimerRepository {
  final write = Completer<void>();

  @override
  Future<bool> hasAccepted(String uid, String version) async => false;

  @override
  Future<void> accept(String uid, String version) => write.future;
}

void main() {
  final user = UserModel(
    uid: 'alice',
    email: 'alice@example.test',
    emailVerified: true,
    createdAt: DateTime.utc(2026),
  );
  final pendingUser = UserModel(
    uid: user.uid,
    email: user.email,
    createdAt: user.createdAt,
  );

  for (final (label, account, hasProfile, accepted, destination) in [
    ('signed-out user', null, false, false, '/login'),
    ('unverified owner with profile', pendingUser, true, true, '/verify-email'),
    ('missing profile', user, false, false, '/health-profile'),
    ('committed acceptance', user, true, true, '/home'),
  ]) {
    testWidgets('dashboard redirect for $label', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWithValue(AsyncData(account)),
          profileExistsProvider.overrideWithValue(AsyncData(hasProfile)),
          disclaimerAcceptedProvider.overrideWithValue(AsyncData(accepted)),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      late BuildContext navigationContext;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            navigationContext = context;
            return const SizedBox.shrink();
          },
        ),
      );
      final match = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri(path: '/home')),
            navigationContext,
          );
      expect(match.uri.path, destination);
    });
  }

  testWidgets('verification replaces the gate and leaves reset reachable', (tester) async {
    final accounts = StreamController<UserModel?>();
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((_) => accounts.stream),
      profileExistsProvider.overrideWithValue(const AsyncData(false)),
      disclaimerAcceptedProvider.overrideWithValue(const AsyncData(false)),
    ]);
    addTearDown(accounts.close);
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, _) {});
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (value) {
      context = value;
      return const SizedBox.shrink();
    }));

    Future<String> destination(String path) async {
      final matches = await router.routeInformationParser.parseRouteInformationWithDependencies(
        RouteInformation(uri: Uri.parse(path)), context,
      );
      return matches.uri.path;
    }

    accounts.add(pendingUser);
    await tester.pump();
    expect(await destination('/medications/add'), '/verify-email');
    expect(await destination('/verify-email'), '/verify-email');
    expect(await destination('/forgot-password'), '/forgot-password');
    accounts.add(user);
    await tester.pump();
    expect(await destination('/verify-email'), '/health-profile');
  });

  ProviderContainer containerFor(DisclaimerRepository repository) {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(AsyncData(user)),
        profileExistsProvider.overrideWithValue(const AsyncData(true)),
        disclaimerRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      disclaimerAcceptedProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return container;
  }

  test(
    'acceptance persists once, belongs to the UID and is version-specific',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreDisclaimerRepository(firestore: firestore);
      final container = containerFor(repository);
      expect(await container.read(disclaimerAcceptedProvider.future), isFalse);
      await container.read(acceptDisclaimerProvider)();
      expect(await container.read(disclaimerAcceptedProvider.future), isTrue);
      await repository.accept(user.uid, currentDisclaimerVersion);
      expect(
        await repository.hasAccepted('other-user', currentDisclaimerVersion),
        isFalse,
      );
      expect(await repository.hasAccepted(user.uid, 'v2'), isFalse);
      final record = await firestore
          .doc('medicalDisclaimerAcceptances/alice/versions/v1')
          .get();
      expect(record.data()?.keys, unorderedEquals(['acceptedAt', 'version']));
      expect(record.data()?['acceptedAt'], isNotNull);
    },
  );

  test(
    'a fresh container reloads acceptance and an account switch clears it',
    () async {
      final repository = FirestoreDisclaimerRepository(
        firestore: FakeFirebaseFirestore(),
      );
      final original = containerFor(repository);
      await original.read(disclaimerAcceptedProvider.future);
      await original.read(acceptDisclaimerProvider)();

      final accounts = StreamController<UserModel?>();
      addTearDown(accounts.close);
      final restarted = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => accounts.stream),
          disclaimerRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(restarted.dispose);
      restarted.listen(authStateProvider, (_, _) {}, fireImmediately: true);
      restarted.listen(
        disclaimerAcceptedProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final initial = restarted.read(disclaimerAcceptedProvider.future);
      accounts.add(user);
      expect(await initial, isTrue);

      accounts.add(null);
      await Future<void>.delayed(Duration.zero);
      await restarted.pump();
      expect(await restarted.read(disclaimerAcceptedProvider.future), isFalse);
      accounts.add(
        UserModel(
          uid: 'bob',
          email: 'bob@example.test',
          createdAt: DateTime.utc(2026),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await restarted.pump();
      expect(await restarted.read(disclaimerAcceptedProvider.future), isFalse);
    },
  );

  testWidgets(
    'direct dashboard navigation is gated and a failed write keeps it gated',
    (tester) async {
      final repository = _FailingRepository();
      final container = containerFor(repository);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      router.go('/home');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DisclaimerAcceptanceScreen), findsOneWidget);
      expect(find.text(MedicalDisclaimer.standardText), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);

      router.go('/notifications/permission');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();
      expect(find.byType(DisclaimerAcceptanceScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);

      await tester.tap(find.text('I accept'));
      await tester.pumpAndSettle();
      expect(find.text('Checking acceptance…'), findsOneWidget);
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsNothing);
      repository.write.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('couldn’t confirm acceptance'),
        findsOneWidget,
      );
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsNothing);
      expect(find.byType(DisclaimerAcceptanceScreen), findsOneWidget);
    },
  );
}
