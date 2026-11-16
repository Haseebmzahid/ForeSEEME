import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/routes/bottom_nav_bar.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/disease_explorer_screen.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/disease_detail_panel.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/disease_trend_chart.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/disease_risk_card.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/environment_orb.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/disease_glass.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/widgets/disease_explorer_entry.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'fixtures.dart';

Future<void> pump(
  WidgetTester tester, {
  Future<RiskEstimateModel?> Function(String)? load,
  Size size = const Size(1000, 1500),
  double scale = 1,
  bool reduce = true,
  bool dark = false,
  bool automaticRetry = true,
  bool highContrast = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: automaticRetry ? null : (_, _) => null,
      overrides: [
        userCityProvider.overrideWith((ref) async => 'Lahore'),
        userConditionsProvider.overrideWith((ref) async => []),
        latestRiskForCityProvider.overrideWith(
          (ref, city) => load?.call(city) ?? Future.value(estimate(city: city)),
        ),
        riskHistoryProvider.overrideWith(
          (ref, city) async => [estimate(city: city, legacy: true)],
        ),
      ],
      child: MaterialApp(
        theme: dark ? ForeSeeMeTheme.dark : ForeSeeMeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduce,
            highContrast: highContrast,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: const RepaintBoundary(
          key: ValueKey('capture'),
          child: DiseaseExplorerScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('Home entry supports large text and announces its action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            highContrast: true,
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: DiseaseExplorerEntry(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Explore Disease Risks. Dengue, Smog and Influenza. Explore now.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets('Map control keeps its visible label at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SizedBox(
            width: 106,
            child: DiseaseExplorerMapAction(city: 'Karachi'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Disease Explorer'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DiseaseExplorerMapAction)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'full-width cards stay stacked in disease order on a wide screen',
    (tester) async {
      await pump(tester);
      final cards = find.byType(DiseaseRiskCard);
      expect(cards, findsNWidgets(3));
      final rectangles = List.generate(3, (i) => tester.getRect(cards.at(i)));
      expect(rectangles[0].width, rectangles[1].width);
      expect(rectangles[1].width, rectangles[2].width);
      expect(rectangles[0].left, rectangles[2].left);
      expect(rectangles[0].bottom, lessThan(rectangles[1].top));
      expect(rectangles[1].bottom, lessThan(rectangles[2].top));
      expect(tester.widget<DiseaseRiskCard>(cards.at(0)).disease, 'dengue');
      expect(tester.widget<DiseaseRiskCard>(cards.at(1)).disease, 'smog');
      expect(tester.widget<DiseaseRiskCard>(cards.at(2)).disease, 'influenza');
    },
  );
  testWidgets(
    'reduced transparency removes feature blur and reduced motion stops the orb',
    (tester) async {
      await pump(tester, highContrast: true);
      await tester.pumpAndSettle();
      expect(find.byType(EnvironmentOrb), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DiseaseGlass),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('refresh retrieves the selected city again', (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      load: (city) async {
        calls.add(city);
        return estimate(city: city);
      },
    );
    await tester.tap(find.byTooltip('Refresh estimates'));
    await tester.pumpAndSettle();
    expect(calls, ['Lahore', 'Lahore']);
  });
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('mobile layout at width $width is readable', (tester) async {
      await pump(tester, size: Size(width, 844), scale: 1.3);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('hero motion renders in theme dark=$dark', (tester) async {
      await pump(
        tester,
        dark: dark,
        reduce: false,
        size: const Size(1000, 1100),
      );
      // The decorative orb intentionally keeps a slow ambient ticker alive.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['DISEASE_EXPLORER_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
            '$directory/explorer_${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets('all three classifications and distinct confidence render', (
    tester,
  ) async {
    await pump(tester);
    for (final text in [
      'Dengue',
      'Smog',
      'Influenza',
      'Medium risk',
      'High risk',
      'Low risk',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Model confidence  80.0%'), findsNWidgets(3));
  });
  testWidgets('city switch reads selected city', (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      load: (city) async {
        calls.add(city);
        return estimate(city: city);
      },
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karachi').last);
    await tester.pumpAndSettle();
    expect(calls, ['Lahore', 'Karachi']);
  });
  testWidgets('legacy documents show missing rather than low risk', (
    tester,
  ) async {
    await pump(tester, load: (_) async => estimate(legacy: true));
    expect(find.text('Not available'), findsNWidgets(3));
    expect(find.text('Low risk'), findsNothing);
  });
  testWidgets('loading and empty states are explicit', (tester) async {
    final pending = Completer<RiskEstimateModel?>();
    await pump(tester, load: (_) => pending.future);
    expect(find.text('Loading independent estimates…'), findsOneWidget);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Missing data does not mean low risk'),
      findsOneWidget,
    );
  });
  for (final offline in [true, false]) {
    testWidgets('error state offline=$offline and retry', (tester) async {
      var calls = 0;
      await pump(
        tester,
        automaticRetry: false,
        load: (_) async {
          calls++;
          throw Exception(offline ? 'unavailable' : 'permission-denied');
        },
      );
      expect(
        find.text(
          offline
              ? 'Offline · no estimate available'
              : 'Could not load estimates',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  }
  testWidgets('automatic retries keep the offline error actionable', (
    tester,
  ) async {
    await pump(tester, load: (_) async => throw Exception('unavailable'));
    expect(find.text('Offline · no estimate available'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Loading independent estimates…'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Offline · no estimate available'), findsOneWidget);
  });
  testWidgets('stale cached and low confidence remain visible', (tester) async {
    final raw = document(at: DateTime.utc(2020));
    (raw['diseaseEstimates'] as List).first['lowConfidence'] = true;
    await pump(
      tester,
      load: (_) async =>
          RiskEstimateModel.fromJson(raw).copyWith(isFromCache: true),
    );
    expect(find.textContaining('Cached data'), findsOneWidget);
    expect(find.textContaining('Stale ·'), findsNWidgets(3));
    expect(find.textContaining('Low confidence'), findsOneWidget);
  });
  testWidgets(
    'disease detail uses selected identity and no fabricated history',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Dengue'));
      await tester.pumpAndSettle();
      expect(find.byType(DiseaseDetailPanel), findsOneWidget);
      expect(find.text('Dengue · Lahore'), findsOneWidget);
      expect(find.text('Medium environmental risk'), findsOneWidget);
      expect(
        find.textContaining('An independent explanation is unavailable'),
        findsOneWidget,
      );
      expect(
        find.textContaining('At least two independent records'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    '320px with 200 percent text and reduced motion has no overflow',
    (tester) async {
      await pump(tester, size: const Size(320, 640), scale: 2);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(AppReveal),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
      );
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('genuine history renders dated category observations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiseaseTrendChart(
            history: [
              estimate().diseaseEstimates.first,
              estimate(at: DateTime.utc(2026, 11, 2)).diseaseEstimates.first,
            ],
          ),
        ),
      ),
    );
    expect(find.text('2026-11-01'), findsOneWidget);
    expect(find.text('2026-11-02'), findsOneWidget);
    expect(find.text('● Medium'), findsNWidgets(2));
  });
  testWidgets('existing five navigation items retain order and callbacks', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavBar(
            currentIndex: 0,
            onTabSelected: taps.add,
          ),
        ),
      ),
    );
    // The existing bar shows text only for its selected item.
    expect(find.text('Home'), findsOneWidget);
    for (final icon in [
      Icons.grid_view_rounded,
      Icons.check_circle_outline_rounded,
      Icons.medication_outlined,
      Icons.menu_book_rounded,
      Icons.person_outline_rounded,
    ]) {
      await tester.tap(find.byIcon(icon));
    }
    expect(taps, [0, 1, 2, 3, 4]);
    expect(find.text('Disease Explorer'), findsNothing);
  });
  testWidgets('history accommodates 200 percent text without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiseaseTrendChart(
              history: [
                estimate().diseaseEstimates.first,
                estimate(at: DateTime.utc(2026, 11, 2)).diseaseEstimates.first,
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('● Medium'), findsNWidgets(2));
  });
  testWidgets('detail labels cached independent history', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          riskHistoryProvider.overrideWith(
            (ref, city) async => [
              estimate(city: city).copyWith(isFromCache: true),
              estimate(
                city: city,
                at: DateTime.utc(2026, 11, 2),
              ).copyWith(isFromCache: true),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DiseaseDetailPanel(
              city: 'Lahore',
              disease: 'dengue',
              estimate: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cached history'), findsOneWidget);
    expect(find.text('2026-11-01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
