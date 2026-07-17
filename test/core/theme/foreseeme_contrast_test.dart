import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_palette.dart';

/// Guards the WCAG AA contrast of the exact ForeSeeMe token pairs the migrated
/// shared widgets (UX-02) render — body text at 4.5:1, interactive/accent colours
/// at the 3:1 UI-component threshold — in both the light and dark themes.
void main() {
  void expectAtLeast(String name, Color fg, Color bg, double min) {
    final ratio = A11y.contrastRatio(fg, bg);
    expect(
      ratio,
      greaterThanOrEqualTo(min),
      reason: '$name = ${ratio.toStringAsFixed(2)}:1 (needs $min:1)',
    );
  }

  for (final p in [ForeSeeMePalette.light, ForeSeeMePalette.dark]) {
    final mode = p.isDark ? 'dark' : 'light';

    group('ForeSeeMe contrast · $mode', () {
      // Body / heading text tiers used by the shared widgets, on the surfaces
      // they actually sit on.
      test('primary & secondary text meet AA (4.5:1) on every surface', () {
        for (final bg in [
          p.background,
          p.surface,
          p.surfaceContainerLow,
          p.surfaceContainerHigh,
        ]) {
          expectAtLeast('textPrimary', p.textPrimary, bg, A11y.aaText);
          expectAtLeast('textSecondary', p.textSecondary, bg, A11y.aaText);
        }
      });

      // Accent used as an outlined-button label / cursor / focus ring, and the
      // filled-button label on the primary fill — UI-component threshold (3:1).
      test('primary accent meets the UI threshold (3:1)', () {
        expectAtLeast('primary on surface', p.primary, p.surface, A11y.aaLargeText);
        expectAtLeast('onPrimary on primary', p.onPrimary, p.primary, A11y.aaLargeText);
      });

      // Status colours used by StatusBadge / semantic surfaces (label + icon).
      test('error/success/warning meet the UI threshold (3:1) on surface', () {
        expectAtLeast('error', p.error, p.surface, A11y.aaLargeText);
        expectAtLeast('success', p.success, p.surface, A11y.aaLargeText);
        expectAtLeast('warning', p.warning, p.surface, A11y.aaLargeText);
      });
    });
  }
}
