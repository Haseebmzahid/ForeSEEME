import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_palette.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

void main() {
  // ── ColorScheme & extension (font-free — resolve directly from the palette) ──
  group('ForeSeeMe ColorScheme', () {
    test('is fully populated from the palette', () {
      final light = ForeSeeMeTheme.lightColorScheme;
      expect(light.brightness, Brightness.light);
      expect(light.primary, ForeSeeMePalette.light.primary);
      expect(light.surface, ForeSeeMePalette.light.surface);
      // Surface tiers (Material 3) are explicitly set, not left to defaults.
      expect(
        light.surfaceContainerHighest,
        ForeSeeMePalette.light.surfaceContainerHighest,
      );

      final dark = ForeSeeMeTheme.darkColorScheme;
      expect(dark.brightness, Brightness.dark);
      expect(dark.primary, ForeSeeMePalette.dark.primary);
    });
  });

  group('ForeSeeMeColors extension', () {
    test('carries status colours + gradients + shadows', () {
      for (final p in [ForeSeeMePalette.light, ForeSeeMePalette.dark]) {
        final ext = ForeSeeMeColors.of(p);
        expect(ext.success, isNotNull);
        expect(ext.warning, isNotNull);
        expect(ext.info, isNotNull);
        expect(ext.gradients.brand.colors.length, greaterThanOrEqualTo(2));
        expect(ext.shadows.medium, isNotEmpty);
      }
    });

    test('resolves distinct values for light vs dark', () {
      final light = ForeSeeMeColors.of(ForeSeeMePalette.light);
      final dark = ForeSeeMeColors.of(ForeSeeMePalette.dark);
      expect(light.success, isNot(dark.success));
    });

    test('lerp interpolates between two extensions', () {
      final a = ForeSeeMeColors.of(ForeSeeMePalette.light);
      final b = ForeSeeMeColors.of(ForeSeeMePalette.dark);
      // Endpoints resolve to themselves; midpoint is neither.
      expect(a.lerp(b, 0.0).success, a.success);
      expect(a.lerp(b, 1.0).success, b.success);
      expect(a.lerp(b, 0.5).success, isNot(a.success));
    });
  });

  // ── Full ThemeData (builds Google Fonts → resolved inside a widget zone) ─────
  group('ForeSeeMeTheme builds', () {
    testWidgets('light theme applies palette background, brightness & extension',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ForeSeeMeTheme.light,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, ForeSeeMePalette.light.background);
      expect(theme.colorScheme.primary, ForeSeeMePalette.light.primary);
      expect(theme.extension<ForeSeeMeColors>(), isNotNull);
    });

    testWidgets('dark theme applies palette background, brightness & extension',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ForeSeeMeTheme.dark,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ForeSeeMePalette.dark.background);
      expect(theme.colorScheme.primary, ForeSeeMePalette.dark.primary);
      expect(theme.extension<ForeSeeMeColors>(), isNotNull);
    });
  });

  // ── ThemeMode.system / light / dark support ─────────────────────────────────
  group('ThemeMode support', () {
    testWidgets('MaterialApp switches light/dark via themeMode', (tester) async {
      Widget app(ThemeMode mode) => MaterialApp(
            theme: ForeSeeMeTheme.light,
            darkTheme: ForeSeeMeTheme.dark,
            themeMode: mode,
            home: const Scaffold(body: SizedBox()),
          );

      await tester.pumpWidget(app(ThemeMode.light));
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );

      await tester.pumpWidget(app(ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
    });
  });
}
