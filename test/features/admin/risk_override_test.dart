import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_repository.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_override_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/repositories/risk_override_repository.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/widgets/risk_card.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

RiskEstimateModel _estimate(RiskLevel level) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: level,
  disease: 'Smog',
  confidence: 0.88,
  temperature: 34,
  humidity: 55,
  aqi: 210,
  generatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
  modelVersion: 'rf-1.0.0',
);

RiskOverride _override({
  RiskLevel level = RiskLevel.high,
  bool active = true,
  DateTime? expiresAt,
}) => RiskOverride(
  city: 'Lahore',
  riskLevel: level,
  disease: 'Smog',
  reason: 'Pipeline delayed; AQI spiked per advisory.',
  authorUid: 'op-1',
  authorEmail: 'op@example.com',
  createdAt: DateTime.now().toUtc(),
  active: active,
  expiresAt: expiresAt,
);

class _FakeOverrideRepo implements RiskOverrideRepository {
  final Map<String, RiskOverride> store = {};
  final List<String> cleared = [];

  @override
  Future<RiskOverride?> getOverride(String city) async => store[city];

  @override
  Future<void> setOverride(RiskOverride override) async {
    store[override.city] = override;
  }

  @override
  Future<void> clearOverride(String city) async {
    cleared.add(city);
    final existing = store[city];
    if (existing != null) store[city] = existing.copyWith(active: false);
  }
}

class _FakeAdmin implements AdminRepository {
  final bool admin;
  _FakeAdmin(this.admin);
  @override
  Future<bool> isCurrentUserAdmin() async => admin;
}

const _cardHost = MaterialApp(
  home: Scaffold(
    backgroundColor: AppColorsV2.shell,
    body: Center(child: RiskCard()),
  ),
);

void main() {
  // ── The override overlay on the risk surface (indicator + applies) ─────────
  group('RiskCard override overlay', () {
    testWidgets('an active override replaces the headline and is labelled', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => _estimate(RiskLevel.low)),
            currentCityOverrideProvider.overrideWith(
              (ref) async => _override(level: RiskLevel.high),
            ),
            riskTrendProvider.overrideWith((ref) async => TrendDirection.stable),
          ],
          child: _cardHost,
        ),
      );
      await tester.pumpAndSettle();

      // Operator value applies (High), clearly labelled, with the reason and the
      // superseded automated estimate shown for transparency.
      expect(find.text('Operator-set'), findsOneWidget);
      expect(find.text('High Risk'), findsOneWidget);
      expect(find.textContaining('Pipeline delayed'), findsOneWidget);
      expect(
        find.textContaining('Automated model estimate: Low Risk'),
        findsOneWidget,
      );
    });

    testWidgets('an override shows even when there is no model estimate', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => null),
            currentCityOverrideProvider.overrideWith(
              (ref) async => _override(level: RiskLevel.medium),
            ),
            riskTrendProvider.overrideWith((ref) async => TrendDirection.stable),
          ],
          child: _cardHost,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Operator-set'), findsOneWidget);
      expect(find.text('Medium Risk'), findsOneWidget);
      expect(find.text('No risk data yet'), findsNothing); // override, not empty
    });

    testWidgets('no override → the normal model card, no operator label', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentCityRiskProvider.overrideWith((ref) async => _estimate(RiskLevel.high)),
            currentCityOverrideProvider.overrideWith((ref) async => null),
            riskTrendProvider.overrideWith((ref) async => TrendDirection.rising),
          ],
          child: _cardHost,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Operator-set'), findsNothing);
      expect(find.text('High Risk'), findsOneWidget);
    });
  });

  // ── Provider filters inactive/expired overrides ────────────────────────────
  group('activeOverrideForCityProvider', () {
    Future<RiskOverride?> read(RiskOverride stored) async {
      final repo = _FakeOverrideRepo()..store['Lahore'] = stored;
      final container = ProviderContainer(
        overrides: [riskOverrideRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      return container.read(activeOverrideForCityProvider('Lahore').future);
    }

    test('returns an active override', () async {
      expect(await read(_override()), isNotNull);
    });

    test('filters a cleared (inactive) override', () async {
      expect(await read(_override(active: false)), isNull);
    });

    test('filters an expired override', () async {
      final expired = _override(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );
      expect(await read(expired), isNull);
    });
  });

  // ── Firestore repository round-trip (real impl, fake backend) ──────────────
  group('FirestoreRiskOverrideRepository', () {
    test('set then get returns the override; clear marks it inactive', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreRiskOverrideRepository(firestore: firestore);

      expect(await repo.getOverride('Lahore'), isNull);

      await repo.setOverride(_override());
      final loaded = await repo.getOverride('Lahore');
      expect(loaded, isNotNull);
      expect(loaded!.riskLevel, RiskLevel.high);
      expect(loaded.authorEmail, 'op@example.com');
      expect(loaded.isActive(), isTrue);

      await repo.clearOverride('Lahore');
      final cleared = await repo.getOverride('Lahore');
      expect(cleared, isNotNull);
      expect(cleared!.isActive(), isFalse); // audit record preserved, inactive
    });
  });

  // ── Admin write controller (author fields from auth; audit recorded) ───────
  group('AdminOverrideController', () {
    // Bare ProviderContainer + StreamProvider.future hangs under Riverpod 3, so
    // we subscribe and let `Stream.value` deliver via a real event-loop turn,
    // then read the resolved value (never `.future`).
    Future<ProviderContainer> ready(_FakeOverrideRepo repo) async {
      final c = ProviderContainer(
        overrides: [
          riskOverrideRepositoryProvider.overrideWithValue(repo),
          userCityProvider.overrideWith((ref) async => 'Lahore'),
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
      addTearDown(c.dispose);
      c.listen(authStateProvider, (_, _) {}); // subscribe so the stream emits
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return c;
    }

    test('submit writes an override stamped with the signed-in author', () async {
      final repo = _FakeOverrideRepo();
      final c = await ready(repo);
      expect(c.read(authStateProvider).value?.uid, 'op-1'); // sanity

      await c.read(adminOverrideControllerProvider.notifier).submit(
            city: 'Lahore',
            riskLevel: RiskLevel.high,
            disease: 'Smog',
            reason: '  AQI spiked  ',
          );

      final written = repo.store['Lahore']!;
      expect(written.riskLevel, RiskLevel.high);
      expect(written.reason, 'AQI spiked'); // trimmed
      expect(written.authorUid, 'op-1'); // from auth, not client-supplied
      expect(written.authorEmail, 'op@example.com');
      expect(written.active, isTrue);
    });

    test('clear delegates to the repository', () async {
      final repo = _FakeOverrideRepo()..store['Lahore'] = _override();
      final c = await ready(repo);

      await c.read(adminOverrideControllerProvider.notifier).clear('Lahore');
      expect(repo.cleared, contains('Lahore'));
      expect(repo.store['Lahore']!.active, isFalse);
    });
  });

  // ── Admin gate ─────────────────────────────────────────────────────────────
  group('isAdminProvider', () {
    Future<bool> read(AdminRepository admin) async {
      final container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(admin),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      return container.read(isAdminProvider.future);
    }

    test('true for an admin user', () async {
      expect(await read(_FakeAdmin(true)), isTrue);
    });

    test('false for a normal user', () async {
      expect(await read(_FakeAdmin(false)), isFalse);
    });

    test('fails closed (false) when the claim read throws', () async {
      expect(await read(_ThrowingAdmin()), isFalse);
    });
  });
}

class _ThrowingAdmin implements AdminRepository {
  @override
  Future<bool> isCurrentUserAdmin() async => throw Exception('token error');
}
