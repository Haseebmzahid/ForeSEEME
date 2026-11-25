import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/domain/repositories/notification_preferences_repository.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/exceptions/health_profile_exception.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/models/health_profile_model.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/repositories/health_profile_repository.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/services/profile_completeness_service.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_model.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_notifier.dart';
import 'package:fyp_foreseeme/features/profile/presentation/profile_screen.dart';
import 'package:fyp_foreseeme/features/profile/presentation/widgets/profile_hub_chrome.dart';
import 'package:fyp_foreseeme/features/profile/presentation/widgets/profile_hub_hero.dart';

/// Covers the Profile Hub: that it renders real provider data rather than the
/// prototype's placeholders, that its interactions still reach the app's
/// existing routes and controllers, that the completeness score is honest, and
/// that the screen survives both themes, 2× text and reduced motion.

// ── Fixtures ─────────────────────────────────────────────────────────────────

UserModel _user({String? displayName = 'Amara Okafor', String? photoUrl}) =>
    UserModel(
      uid: 'u1',
      email: 'amara@example.com',
      displayName: displayName,
      photoUrl: photoUrl,
      emailVerified: true,
      createdAt: DateTime.utc(2026, 1, 1),
    );

HealthProfileModel _profile({
  String city = 'Lahore',
  List<String> conditions = const ['asthma'],
}) => HealthProfileModel(
  uid: 'u1',
  city: city,
  chronicConditions: conditions,
  lastUpdated: DateTime.utc(2026, 1, 1),
);

MedicationModel _medication({List<String> reminderTimes = const ['08:00']}) =>
    MedicationModel(
      id: 'm1',
      uid: 'u1',
      name: 'Ventolin',
      dosage: '2 puffs',
      type: MedicationType.pill,
      frequency: MedicationFrequency.onceDaily,
      reminderTimes: reminderTimes,
      isActive: true,
      createdAt: DateTime.utc(2026, 1, 1),
    );

class _FakeHealthProfileRepository implements HealthProfileRepository {
  _FakeHealthProfileRepository(this._result);

  final Either<HealthProfileException, HealthProfileModel?> _result;

  @override
  Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(
    String uid,
  ) async => _result;

  @override
  Future<Either<HealthProfileException, void>> saveProfile(
    HealthProfileModel profile,
  ) async => throw UnimplementedError();

  @override
  Future<Either<HealthProfileException, void>> updateProfile(
    String uid, {
    String? city,
    List<String>? conditions,
    List<String>? customConditions,
  }) async => throw UnimplementedError();
}

/// Records what the Profile Hub's master switch persists.
class _RecordingPreferencesRepository
    implements NotificationPreferencesRepository {
  _RecordingPreferencesRepository(this.initial);

  final NotificationPreferences initial;
  final List<NotificationPreferences> saved = [];

  @override
  Future<NotificationPreferences> load(String uid) async => initial;

  @override
  Future<void> save(String uid, NotificationPreferences preferences) async {
    saved.add(preferences);
  }
}

/// Routes the Profile Hub actually navigates to, so a tap can be asserted
/// without standing up the whole app router.
final List<String> _visited = [];

GoRouter _router() => GoRouter(
  initialLocation: '/profile',
  routes: [
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
      routes: const [],
    ),
    for (final path in const [
      '/health-profile',
      '/notifications/settings',
      '/resources',
      '/admin/dashboard',
    ])
      GoRoute(
        path: path,
        builder: (context, state) {
          _visited.add(path);
          return const Scaffold(body: Text('destination'));
        },
      ),
  ],
);

Widget _host({
  UserModel? user,
  HealthProfileModel? profile,
  HealthProfileException? profileError,
  List<MedicationModel> medications = const [],
  bool isAdmin = false,
  NotificationPreferencesRepository? preferences,
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  bool reduceMotion = false,
}) {
  final resolvedUser = user ?? _user();

  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream<UserModel?>.value(resolvedUser),
      ),
      healthProfileRepositoryProvider.overrideWithValue(
        _FakeHealthProfileRepository(
          profileError != null
              ? Left<HealthProfileException, HealthProfileModel?>(profileError)
              : Right<HealthProfileException, HealthProfileModel?>(profile),
        ),
      ),
      medicationsStreamProvider.overrideWith((ref) => Stream.value(medications)),
      isAdminProvider.overrideWith((ref) async => isAdmin),
      notificationPreferencesRepositoryProvider.overrideWithValue(
        preferences ??
            _RecordingPreferencesRepository(
              NotificationPreferences.defaults(),
            ),
      ),
    ],
    child: MaterialApp.router(
      theme: ForeSeeMeTheme.light,
      darkTheme: ForeSeeMeTheme.dark,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      routerConfig: _router(),
      // Only the properties the real device would add on top of the view are
      // overridden here; the surface size itself comes from `_surface`, so
      // layout and hit-testing agree (a MediaQuery-only size would lay the
      // screen out at one size and hit-test it at another).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
          padding: const EdgeInsets.only(top: 24),
        ),
        child: child!,
      ),
    ),
  );
}

/// Sets the real test surface to a phone-sized viewport.
///
/// Without this the render tree stays at the harness default of 800×600, which
/// both misreports the layout and puts most of the screen outside the hit-test
/// bounds.
void _surface(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Finds a widget by the semantics label it declares.
///
/// Deliberately matches the [Semantics] widget rather than using
/// `find.bySemanticsLabel`, which needs the semantics tree switched on for the
/// whole test and its handle disposed before the body ends — a lifecycle that
/// `addTearDown` runs too late to satisfy.
Finder _byLabel(Pattern label) => find.byWidgetPredicate((widget) {
  if (widget is! Semantics) return false;
  final actual = widget.properties.label;
  if (actual == null) return false;
  return label is RegExp
      ? label.hasMatch(actual)
      : actual == label;
});

/// Settles the providers without waiting on the ambient loops, which never
/// stop and would hang `pumpAndSettle`.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scrolls until [finder] is built.
///
/// The Hub is a lazily-built list taller than any supported viewport, so the
/// lower cards genuinely do not exist until scrolled to — exercising the real
/// scroll path rather than inflating the viewport to hide that. Hand-rolled
/// rather than `scrollUntilVisible`, which settles the tree and would hang on
/// the ambient loops.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 25 && finder.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(finder, findsWidgets, reason: 'never scrolled into view');
}

void main() {
  setUp(_visited.clear);

  // ── Domain: the score is honest ────────────────────────────────────────────

  group('ProfileCompletenessService', () {
    const service = ProfileCompletenessService();

    test('is zero when nothing is on file', () {
      final score = service.score(
        displayName: null,
        photoUrl: null,
        hasProfile: false,
        city: null,
        chronicConditions: const [],
        activeMedicationCount: 0,
        medicationsWithRemindersCount: 0,
      );

      expect(score.percent, 0);
      expect(score.isEmpty, isTrue);
      expect(score.components, hasLength(3));
      expect(score.components.every((c) => c.percent == 0), isTrue);
    });

    test('is 100 only when every check is satisfied', () {
      final score = service.score(
        displayName: 'Amara Okafor',
        photoUrl: 'https://example.com/a.png',
        hasProfile: true,
        city: 'Lahore',
        chronicConditions: const ['asthma'],
        activeMedicationCount: 1,
        medicationsWithRemindersCount: 1,
      );

      expect(score.percent, 100);
      expect(score.components.every((c) => c.isComplete), isTrue);
    });

    test('weights by check count, not by component', () {
      // Three of six checks satisfied → 50%, even though the satisfied checks
      // are spread unevenly across components.
      final score = service.score(
        displayName: 'Amara Okafor',
        photoUrl: null,
        hasProfile: true,
        city: 'Lahore',
        chronicConditions: const [],
        activeMedicationCount: 1,
        medicationsWithRemindersCount: 0,
      );

      expect(score.percent, 50);
    });

    test('ignores profile fields entirely when no profile exists', () {
      final score = service.score(
        displayName: null,
        photoUrl: null,
        hasProfile: false,
        city: 'Lahore',
        chronicConditions: const ['asthma'],
        activeMedicationCount: 0,
        medicationsWithRemindersCount: 0,
      );

      expect(score.percent, 0);
    });

    test('treats whitespace-only values as absent', () {
      final score = service.score(
        displayName: '   ',
        photoUrl: '',
        hasProfile: true,
        city: '  ',
        chronicConditions: const [],
        activeMedicationCount: 0,
        medicationsWithRemindersCount: 0,
      );

      expect(score.percent, 0);
    });
  });

  // ── Rendering + real data ──────────────────────────────────────────────────

  group('Profile Hub rendering', () {
    testWidgets('renders the route with the prototype\'s sections', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(ProfileHubHero), findsOneWidget);
      expect(find.text('Health Profile'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);
      expect(find.text('SYSTEM LIVE'), findsOneWidget);
      expect(
        find.text('Your health system is under your control'),
        findsOneWidget,
      );

      await _scrollTo(tester, find.text('Privacy'));
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('SECURED'), findsOneWidget);

      await _scrollTo(tester, find.text('Help Center'));
      expect(find.text('Help Center'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('shows the signed-in user rather than the prototype name', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _host(user: _user(displayName: 'Fatima Noor'), profile: _profile()),
      );
      await _settle(tester);

      expect(find.text('Fatima Noor'), findsOneWidget);
      // The prototype's placeholder must not survive into the app.
      expect(find.text('Amara Okafor'), findsNothing);
    });

    testWidgets('shows the computed completeness, not the prototype 82%', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _host(
          user: _user(photoUrl: 'https://example.com/a.png'),
          profile: _profile(),
          medications: [_medication()],
        ),
      );
      await _settle(tester);

      // Every check satisfied.
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('100% READY'), findsOneWidget);
      expect(find.text('82%'), findsNothing);
    });

    testWidgets('reports an honest em dash while the profile read is in flight',
        (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await tester.pump(); // first frame only — providers still resolving

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('renders the real next reminder time', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _host(
          profile: _profile(),
          medications: [_medication(reminderTimes: const ['23:45'])],
        ),
      );
      await _settle(tester);

      expect(find.text('NEXT · 23:45'), findsOneWidget);
    });

    testWidgets('states plainly when no reminder is scheduled', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      expect(find.text('NONE SCHEDULED'), findsOneWidget);
      expect(find.textContaining('NEXT ·'), findsNothing);
    });

    testWidgets('hides the admin slab from non-operators', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('ADMIN PANEL'), findsNothing);
    });

    testWidgets('shows the admin slab to operators', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile(), isAdmin: true));
      await _settle(tester);

      await _scrollTo(tester, find.text('ADMIN PANEL'));
      expect(find.text('ADMIN PANEL'), findsOneWidget);
      expect(find.text('OPERATOR'), findsOneWidget);
    });

    testWidgets('survives a failed profile read without inventing a figure', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _host(profileError: const HealthProfileException('offline')),
      );
      await _settle(tester);

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── Interaction ────────────────────────────────────────────────────────────

  group('Profile Hub interaction', () {
    testWidgets('expands and collapses the Health Profile card', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _host(profile: _profile(), medications: [_medication()]),
      );
      await _settle(tester);

      expect(find.text('TAP TO OPEN FULL PROFILE'), findsNothing);

      await tester.tap(find.text('Health Profile'));
      await _settle(tester);

      expect(find.text('TAP TO OPEN FULL PROFILE'), findsOneWidget);
      // The real score components, not the prototype's Conditions/Medications/
      // Allergies placeholders — the app models no allergies.
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Conditions'), findsOneWidget);
      expect(find.text('Medications'), findsOneWidget);
      expect(find.text('Allergies'), findsNothing);

      await tester.tap(find.text('Health Profile'));
      await _settle(tester);

      expect(find.text('TAP TO OPEN FULL PROFILE'), findsNothing);
    });

    testWidgets('opens the full health profile from the expanded footer', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      await tester.tap(find.text('Health Profile'));
      await _settle(tester);
      await tester.tap(find.text('TAP TO OPEN FULL PROFILE'));
      await _settle(tester);

      expect(_visited, contains('/health-profile'));
    });

    testWidgets('opens notification settings from the Notifications card', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      await tester.tap(find.text('Alerts & sounds'));
      await _settle(tester);

      expect(_visited, contains('/notifications/settings'));
    });

    testWidgets('opens the Resource Center from Help Center', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      await _scrollTo(tester, find.text('OPEN PORTAL →'));
      await tester.tap(find.text('OPEN PORTAL →'));
      await _settle(tester);

      expect(_visited, contains('/resources'));
    });

    testWidgets('opens the admin dashboard from the admin slab', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile(), isAdmin: true));
      await _settle(tester);

      await _scrollTo(tester, find.text('ADMIN PANEL'));
      await tester.tap(find.text('ADMIN PANEL'));
      await _settle(tester);

      expect(_visited, contains('/admin/dashboard'));
    });

    testWidgets('the master switch mutes every risk category in one write', (
      tester,
    ) async {
      final repository = _RecordingPreferencesRepository(
        NotificationPreferences.defaults(),
      );
      _surface(tester);
      await tester.pumpWidget(
        _host(profile: _profile(), preferences: repository),
      );
      await _settle(tester);

      expect(find.text('ACTIVE'), findsOneWidget);

      await tester.tap(find.byType(HubSwitch));
      await _settle(tester);

      expect(repository.saved, hasLength(1));
      final muted = repository.saved.single;
      expect(muted.highRiskAlerts, isFalse);
      expect(muted.mediumRiskAlerts, isFalse);
      expect(muted.lowRiskUpdates, isFalse);
      // Condition selections are preserved through a mute.
      expect(
        muted.conditions,
        NotificationPreferences.defaults().conditions,
      );
      expect(find.text('MUTED'), findsOneWidget);
    });

    testWidgets('un-muting restores the documented defaults, not everything', (
      tester,
    ) async {
      final repository = _RecordingPreferencesRepository(
        const NotificationPreferences(
          highRiskAlerts: false,
          mediumRiskAlerts: false,
          lowRiskUpdates: false,
          conditions: {'respiratory': true, 'cardiovascular': false},
        ),
      );
      _surface(tester);
      await tester.pumpWidget(
        _host(profile: _profile(), preferences: repository),
      );
      await _settle(tester);

      expect(find.text('MUTED'), findsOneWidget);

      await tester.tap(find.byType(HubSwitch));
      await _settle(tester);

      final restored = repository.saved.single;
      expect(restored.highRiskAlerts, isTrue);
      expect(restored.mediumRiskAlerts, isTrue);
      // Low-risk updates stay off — un-muting must not opt the user into more.
      expect(restored.lowRiskUpdates, isFalse);
    });

    testWidgets('the theme switcher selects light and dark', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      final dark = tester.widget<HubThemeSwitch>(find.byType(HubThemeSwitch));
      expect(dark.isDarkSelected, isTrue);

      // Both options are reachable as buttons with distinct semantics.
      expect(
        _byLabel('Light theme'),
        findsOneWidget,
      );
      expect(_byLabel('Dark theme'), findsOneWidget);
    });
  });

  // ── Accessibility ──────────────────────────────────────────────────────────

  group('Profile Hub accessibility', () {
    testWidgets('interactive cards expose button semantics', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile(), isAdmin: true));
      await _settle(tester);

      expect(
        _byLabel(RegExp('^Health profile,')),
        findsOneWidget,
      );
      expect(
        _byLabel('Notifications, alerts and sounds'),
        findsOneWidget,
      );
      expect(_byLabel('Risk alerts'), findsOneWidget);

      await _scrollTo(
        tester,
        _byLabel('Help Center, guides, FAQs and support'),
      );
      expect(
        _byLabel('Help Center, guides, FAQs and support'),
        findsOneWidget,
      );
      await _scrollTo(
        tester,
        _byLabel('Admin panel, system operations, restricted'),
      );
      expect(
        _byLabel('Admin panel, system operations, restricted'),
        findsOneWidget,
      );
    });

    testWidgets('the expandable card announces its expanded state', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      expect(
        tester.getSemantics(
          _byLabel(RegExp('^Health profile,')),
        ),
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      await tester.tap(find.text('Health Profile'));
      await _settle(tester);

      expect(
        tester.getSemantics(
          _byLabel(RegExp('^Health profile,')),
        ),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );

    });

    testWidgets('the notification switch keeps a 48dp target', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      final size = tester.getSize(find.byType(HubSwitch));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('theme options keep a 44dp+ target at default scale', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      final size = tester.getSize(_byLabel('Light theme'));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  // ── Themes, scale and motion ───────────────────────────────────────────────

  group('Profile Hub adaptivity', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders in ${brightness.name} theme', (tester) async {
        _surface(tester);
        await tester.pumpWidget(
          _host(profile: _profile(), brightness: brightness),
        );
        await _settle(tester);

        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.text('Health Profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final size in const [
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
    ]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        testWidgets(
          'lays out at ${size.width.toInt()}×${size.height.toInt()} @ ${scale}x',
          (tester) async {
            _surface(tester, size);
            await tester.pumpWidget(
              _host(
                profile: _profile(),
                isAdmin: true,
                medications: [_medication()],
                textScale: scale,
              ),
            );
            await _settle(tester);

            // The screen scrolls, so nothing may overflow horizontally and no
            // layout may throw at any of the supported scales.
            expect(tester.takeException(), isNull);
            expect(find.byType(ProfileScreen), findsOneWidget);
          },
        );
      }
    }

    testWidgets('reduced motion parks the ambient loops', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _host(profile: _profile(), reduceMotion: true),
      );
      await _settle(tester);

      // With every loop dropped there is no ticker left to schedule a frame,
      // so the tree genuinely settles — which it cannot do while the orbit
      // rings and equalizer are running.
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(ProfileHubHero), findsOneWidget);
    });

    testWidgets('ambient loops keep animating when motion is allowed', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
_host(profile: _profile()));
      await _settle(tester);

      // Explicit checkpoints rather than pumpAndSettle, which would never
      // return against an infinite loop.
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });
  });

  // ── Layering ───────────────────────────────────────────────────────────────

  testWidgets('the screen reaches no repository directly', (tester) async {
    // The Hub composes providers only; if it were talking to Firebase this
    // test would fail to build at all in a unit-test binding. Overriding every
    // repository the screen's providers depend on is therefore sufficient
    // proof that no widget opens its own data path.
    _surface(tester);
    await tester.pumpWidget(
_host(profile: _profile()));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
