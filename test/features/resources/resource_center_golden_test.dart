@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_center_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// Renders the Resource Center across the sizes, themes and text scales the
/// design review covers, so the layout can be compared against the approved
/// prototype (`docs/Design/ForeSeeMe Resource Center.html`) rather than
/// eyeballed.
///
/// Tagged `golden` and excluded from the default run (see `dart_test.yaml`).
/// Regenerate with:
///
/// ```
/// flutter test --tags golden --run-skipped --update-goldens
/// ```
///
/// Glyphs render as the test font's boxes — these goldens are about geometry,
/// depth, gradients, the field object and rhythm, not letterforms.

RiskEstimateModel _estimate(RiskLevel level) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: level,
  disease: 'Dengue',
  confidence: 0.86,
  temperature: 31.0,
  humidity: 54.0,
  aqi: 214.0,
  generatedAt: DateTime.utc(2026, 6, 28),
  modelVersion: '1.0.0',
);

NearbyHospitalsResult _fixtureCare() => NearbyHospitalsResult(
  hospitals: const [
    Hospital(
      id: 'h1',
      name: 'Jinnah Hospital Lahore',
      address: 'Ring Rd',
      latitude: 31.5,
      longitude: 74.3,
      distanceKm: 2.4,
      openNow: true,
    ),
    Hospital(
      id: 'h2',
      name: 'Services Hospital',
      address: 'Jail Rd',
      latitude: 31.54,
      longitude: 74.33,
      distanceKm: 3.1,
    ),
    Hospital(
      id: 'h3',
      name: 'Mayo Hospital',
      address: 'Hospital Rd',
      latitude: 31.57,
      longitude: 74.31,
      distanceKm: 5.8,
      openNow: false,
    ),
  ],
  fetchedAt: DateTime(2026, 6, 28, 9),
  servedFromCache: false,
);

GoRouter _router({String initialLocation = '/resources'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/resources',
      builder: (context, state) => const ResourceCenterScreen(),
      routes: [
        GoRoute(
          path: 'article/:articleId',
          builder: (context, state) =>
              ArticleScreen(articleId: state.pathParameters['articleId']!),
        ),
      ],
    ),
    GoRoute(
      path: '/nearby-hospitals',
      builder: (context, state) => const Scaffold(body: Text('Directory')),
    ),
  ],
);

Widget _host({
  required Brightness brightness,
  double textScale = 1.0,
  RiskLevel? risk,
  String initialLocation = '/resources',
  bool withFixtureCare = false,
}) => ProviderScope(
  overrides: [
    // Design-review fixture only: the real lookup needs a device location and
    // a Places key, neither of which exist in a widget test. It never leaves
    // this file.
    if (withFixtureCare)
      nearbyHospitalsProvider.overrideWith((ref) async => _fixtureCare()),
    resourceRepositoryProvider.overrideWithValue(const StaticResourceRepository()),
    bookmarkOwnerProvider.overrideWithValue(null),
    userCityProvider.overrideWith((ref) => risk == null ? null : 'Lahore'),
    if (risk != null)
      riskRepositoryProvider.overrideWithValue(
        FakeRiskRepository(seed: {'Lahore': _estimate(risk)}),
      ),
  ],
  child: MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: ForeSeeMeTheme.light,
    darkTheme: ForeSeeMeTheme.dark,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    routerConfig: _router(initialLocation: initialLocation),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        // `AppShell` runs `Scaffold(extendBody: true)`, so in the real app
        // Flutter reports `AppBottomNavBar`'s 100px height as this screen's
        // bottom inset. Reproducing it here puts the bottom composition where
        // the review needs to see it.
        padding: const EdgeInsets.only(top: 24, bottom: 100),
      ),
      child: child!,
    ),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);


  const sizes = <String, Size>{
    '360x800': Size(360, 800),
    '390x844': Size(390, 844),
    '430x932': Size(430, 932),
  };

  // The field's ambient motion is driven by one clock; a single 5s pump puts
  // every loop at the same phase the prototype's own headless render sits at,
  // so the two frames are directly comparable.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5000));
  }

  for (final brightness in Brightness.values) {
    for (final entry in sizes.entries) {
      testWidgets('resources ${brightness.name} ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(brightness: brightness));
        await settle(tester);

        await expectLater(
          find.byType(ResourceCenterScreen),
          matchesGoldenFile('goldens/rc_${brightness.name}_${entry.key}.png'),
        );
      });
    }
  }

  // Everything below the field — the rail, the grid, the radar and the
  // catalogue — sits under the fold on every supported size.
  for (final brightness in Brightness.values) {
    for (final drag in const [320.0, 900.0, 1500.0]) {
      testWidgets(
        'resources ${brightness.name} 390x844 scrolled ${drag.toInt()}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_host(brightness: brightness));
          await settle(tester);

          await tester.drag(
            find.byType(Scrollable).first,
            Offset(0, -drag),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 600));

          await expectLater(
            find.byType(ResourceCenterScreen),
            matchesGoldenFile(
              'goldens/rc_${brightness.name}_scroll${drag.toInt()}.png',
            ),
          );
        },
      );
    }
  }

  // One tall frame per theme so the whole composition — field, rail, grid,
  // radar and catalogue — can be checked against the prototype in one look.
  for (final brightness in Brightness.values) {
    testWidgets('resources ${brightness.name} full page', (tester) async {
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(brightness: brightness));
      await settle(tester);

      await expectLater(
        find.byType(ResourceCenterScreen),
        matchesGoldenFile('goldens/rc_${brightness.name}_full.png'),
      );
    });
  }

  // The field is energy-reactive: no signal is grey, Medium amber, High coral.
  for (final risk in const [null, RiskLevel.low, RiskLevel.medium, RiskLevel.high]) {
    testWidgets('resources dark field ${risk?.name ?? 'nosignal'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(brightness: Brightness.dark, risk: risk),
      );
      await settle(tester);

      await expectLater(
        find.byType(ResourceCenterScreen),
        matchesGoldenFile('goldens/rc_dark_energy_${risk?.name ?? 'none'}.png'),
      );
    });
  }

  // The article detail, at both themes and at the largest supported text
  // scale — its header composition is the piece most at risk from scaling.
  for (final brightness in Brightness.values) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('article ${brightness.name} @${scale}x', (tester) async {
        tester.view.physicalSize = const Size(390, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            brightness: brightness,
            textScale: scale,
            risk: RiskLevel.medium,
            initialLocation: '/resources/article/lungs-smog',
          ),
        );
        await settle(tester);

        await expectLater(
          find.byType(ArticleScreen),
          matchesGoldenFile('goldens/rc_article_${brightness.name}_$scale.png'),
        );
      });
    }
  }

  // The three overlays. Each is a root-navigator route, so the frame is
  // captured from the whole view rather than the screen widget.
  for (final brightness in Brightness.values) {
    testWidgets('overlay ${brightness.name} emergency', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(brightness: brightness));
      await settle(tester);

      await tester.tap(find.text('Need help now?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rc_${brightness.name}_emergency.png'),
      );
    });

    testWidgets('overlay ${brightness.name} search', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(brightness: brightness));
      await settle(tester);

      await tester.tap(find.text('Search verified guidance'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), 'air');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rc_${brightness.name}_search.png'),
      );
    });
  }

  // The care section, resolved, and then one facility's sheet.
  for (final brightness in Brightness.values) {
    testWidgets('overlay ${brightness.name} care', (tester) async {
      tester.view.physicalSize = const Size(390, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(brightness: brightness, withFixtureCare: true),
      );
      await settle(tester);

      await tester.tap(find.text('FIND CARE NEAR ME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await expectLater(
        find.byType(ResourceCenterScreen),
        matchesGoldenFile('goldens/rc_${brightness.name}_care.png'),
      );
    });
  }

  testWidgets('overlay dark facility sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        brightness: Brightness.dark,
        withFixtureCare: true,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('FIND CARE NEAR ME'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Jinnah Hospital Lahore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rc_dark_facility.png'),
    );
  });

  for (final scale in const [1.5, 2.0]) {
    for (final drag in const [0.0, 900.0]) {
      testWidgets('resources dark 390x844 @${scale}x scroll${drag.toInt()}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            brightness: Brightness.dark,
            textScale: scale,
          ),
        );
        await settle(tester);

        if (drag > 0) {
          await tester.drag(
            find.byType(Scrollable).first,
            Offset(0, -drag),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 600));
        }

        await expectLater(
          find.byType(ResourceCenterScreen),
          matchesGoldenFile(
            'goldens/rc_dark_scale_${scale}_scroll${drag.toInt()}.png',
          ),
        );
      });
    }
  }
}
