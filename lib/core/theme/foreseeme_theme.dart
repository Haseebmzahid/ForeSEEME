import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'foreseeme_palette.dart';
import 'foreseeme_tokens.dart';
import 'foreseeme_typography.dart';

/// ForeSeeMe premium design-system — **gradients** (resolved from a palette).
class ForeSeeMeGradients {
  const ForeSeeMeGradients({
    required this.brand,
    required this.primary,
    required this.surface,
  });

  /// Identity gradient (violet → blue → teal).
  final LinearGradient brand;

  /// Primary-action gradient (health-green shades).
  final LinearGradient primary;

  /// Subtle app-background gradient.
  final LinearGradient surface;

  factory ForeSeeMeGradients.of(ForeSeeMePalette p) => ForeSeeMeGradients(
    brand: LinearGradient(
      colors: p.gradientBrand,
      stops: const [0.0, 0.52, 1.0],
      begin: const Alignment(-1, -0.3),
      end: const Alignment(1, 0.3),
    ),
    primary: LinearGradient(
      colors: p.gradientPrimary,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    surface: LinearGradient(
      colors: p.gradientSurface,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.56, 1.0],
    ),
  );

  static ForeSeeMeGradients lerp(
    ForeSeeMeGradients a,
    ForeSeeMeGradients b,
    double t,
  ) => t < 0.5 ? a : b;
}

/// ForeSeeMe premium design-system — **elevation shadows** (resolved from a
/// palette). Recipes pair with [ForeSeeMeElevation] levels.
class ForeSeeMeShadows {
  const ForeSeeMeShadows({
    required this.soft,
    required this.medium,
    required this.strong,
  });

  final List<BoxShadow> soft;
  final List<BoxShadow> medium;
  final List<BoxShadow> strong;

  factory ForeSeeMeShadows.of(ForeSeeMePalette p) {
    final s = p.shadow;
    // Dark UIs need a heavier ambient shadow to read; light UIs stay airy.
    final k = p.isDark ? 1.6 : 1.0;
    return ForeSeeMeShadows(
      soft: [
        BoxShadow(
          color: s.withValues(alpha: 0.06 * k),
          blurRadius: 12,
          spreadRadius: -6,
          offset: const Offset(0, 6),
        ),
      ],
      medium: [
        BoxShadow(
          color: s.withValues(alpha: 0.10 * k),
          blurRadius: 24,
          spreadRadius: -10,
          offset: const Offset(0, 12),
        ),
      ],
      strong: [
        BoxShadow(
          color: s.withValues(alpha: 0.16 * k),
          blurRadius: 40,
          spreadRadius: -12,
          offset: const Offset(0, 20),
        ),
      ],
    );
  }

  static ForeSeeMeShadows lerp(
    ForeSeeMeShadows a,
    ForeSeeMeShadows b,
    double t,
  ) => t < 0.5 ? a : b;
}

/// ForeSeeMe premium design-system — **semantic colour extension**.
///
/// [ThemeExtension] is the idiomatic, non-invasive way to hang design tokens off
/// [ThemeData] that Material's `ColorScheme` does not model — here: the
/// **success / warning / info** status families, plus resolved [gradients] and
/// [shadows]. Once screens migrate they read these via
/// `Theme.of(context).extension<ForeSeeMeColors>()!`, so the values always
/// track the active light/dark theme from a single source.
///
/// (Base roles — primary / secondary / tertiary / error / surfaces / outline —
/// are already carried by [ColorScheme]; they are intentionally not duplicated
/// here.)
@immutable
class ForeSeeMeColors extends ThemeExtension<ForeSeeMeColors> {
  const ForeSeeMeColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.textTertiary,
    required this.gradients,
    required this.shadows,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  /// Third-tier text tone (below `onSurfaceVariant`) for meta/captions.
  final Color textTertiary;

  final ForeSeeMeGradients gradients;
  final ForeSeeMeShadows shadows;

  factory ForeSeeMeColors.of(ForeSeeMePalette p) => ForeSeeMeColors(
    success: p.success,
    onSuccess: p.onSuccess,
    successContainer: p.successContainer,
    onSuccessContainer: p.onSuccessContainer,
    warning: p.warning,
    onWarning: p.onWarning,
    warningContainer: p.warningContainer,
    onWarningContainer: p.onWarningContainer,
    info: p.info,
    onInfo: p.onInfo,
    infoContainer: p.infoContainer,
    onInfoContainer: p.onInfoContainer,
    textTertiary: p.textTertiary,
    gradients: ForeSeeMeGradients.of(p),
    shadows: ForeSeeMeShadows.of(p),
  );

  @override
  ForeSeeMeColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? textTertiary,
    ForeSeeMeGradients? gradients,
    ForeSeeMeShadows? shadows,
  }) => ForeSeeMeColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    info: info ?? this.info,
    onInfo: onInfo ?? this.onInfo,
    infoContainer: infoContainer ?? this.infoContainer,
    onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    textTertiary: textTertiary ?? this.textTertiary,
    gradients: gradients ?? this.gradients,
    shadows: shadows ?? this.shadows,
  );

  @override
  ForeSeeMeColors lerp(ThemeExtension<ForeSeeMeColors>? other, double t) {
    if (other is! ForeSeeMeColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ForeSeeMeColors(
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      successContainer: c(successContainer, other.successContainer),
      onSuccessContainer: c(onSuccessContainer, other.onSuccessContainer),
      warning: c(warning, other.warning),
      onWarning: c(onWarning, other.onWarning),
      warningContainer: c(warningContainer, other.warningContainer),
      onWarningContainer: c(onWarningContainer, other.onWarningContainer),
      info: c(info, other.info),
      onInfo: c(onInfo, other.onInfo),
      infoContainer: c(infoContainer, other.infoContainer),
      onInfoContainer: c(onInfoContainer, other.onInfoContainer),
      textTertiary: c(textTertiary, other.textTertiary),
      gradients: ForeSeeMeGradients.lerp(gradients, other.gradients, t),
      shadows: ForeSeeMeShadows.lerp(shadows, other.shadows, t),
    );
  }
}

/// Ergonomic access to the ForeSeeMe design system from a [BuildContext].
///
/// Every screen consumes the design system through these accessors instead of
/// reaching for a raw `Colors.*` literal. Both are **brightness-aware** (they
/// read `Theme.of(context).brightness`, so `ThemeMode.system/light/dark` are
/// honoured); [fsmColors] prefers the theme-attached [ForeSeeMeColors]
/// extension when present, falling back to resolving the palette directly.
extension ForeSeeMeContext on BuildContext {
  /// The base ForeSeeMe palette (brand, surfaces, text, outlines, effects) for
  /// the ambient brightness.
  ForeSeeMePalette get fsmPalette =>
      ForeSeeMePalette.of(Theme.of(this).brightness);

  /// The ForeSeeMe semantic colours (success / warning / info) plus gradients
  /// and shadows — from the attached extension when present, else the palette.
  ForeSeeMeColors get fsmColors =>
      Theme.of(this).extension<ForeSeeMeColors>() ??
      ForeSeeMeColors.of(fsmPalette);

  /// The ForeSeeMe [TextTheme] for the ambient brightness (Space Grotesk +
  /// Manrope, colours resolved from the palette). Use with `.copyWith(...)` when
  /// a widget needs a role's shape but a semantic (status) colour.
  TextTheme get fsmText => ForeSeeMeTypography.textTheme(fsmPalette);

  /// The ForeSeeMe **instrumentation** styles (IBM Plex Mono readouts, channel
  /// labels, telemetry values) for the ambient brightness. Use only for measured
  /// values and their labels — never for prose. See [ForeSeeMeTelemetry].
  ForeSeeMeTelemetry get fsmTelemetry => ForeSeeMeTelemetry.of(fsmPalette);
}

/// ForeSeeMe premium design-system — **the theme** (single entry point).
///
/// [ForeSeeMeTheme] is the one source of truth every screen consumes. It
/// exposes:
///
///  * [light] / [dark] — fully-built [ThemeData] (Material 3), including a
///    complete [ColorScheme], the [ForeSeeMeTypography] text theme, component
///    themes shaped from [ForeSeeMeRadius] / [ForeSeeMeElevation], and the
///    [ForeSeeMeColors] extension for status colours, gradients and shadows.
///  * [lightColorScheme] / [darkColorScheme] — the schemes on their own.
///
/// Support for `ThemeMode.system` / `.light` / `.dark` is provided by handing
/// [light] and [dark] to `MaterialApp`; the app's existing `themeNotifierProvider`
/// already drives `themeMode`.
///
/// **No raw colour literal appears in this file** — every colour is resolved
/// from a [ForeSeeMePalette].
class ForeSeeMeTheme {
  ForeSeeMeTheme._();

  static ColorScheme get lightColorScheme =>
      _colorScheme(ForeSeeMePalette.light);

  static ColorScheme get darkColorScheme => _colorScheme(ForeSeeMePalette.dark);

  static ThemeData get light => _build(ForeSeeMePalette.light);

  static ThemeData get dark => _build(ForeSeeMePalette.dark);

  static ColorScheme _colorScheme(ForeSeeMePalette p) => ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    secondaryContainer: p.secondaryContainer,
    onSecondaryContainer: p.onSecondaryContainer,
    tertiary: p.tertiary,
    onTertiary: p.onTertiary,
    tertiaryContainer: p.tertiaryContainer,
    onTertiaryContainer: p.onTertiaryContainer,
    error: p.error,
    onError: p.onError,
    errorContainer: p.errorContainer,
    onErrorContainer: p.onErrorContainer,
    surface: p.surface,
    onSurface: p.onSurface,
    onSurfaceVariant: p.onSurfaceVariant,
    surfaceDim: p.surfaceDim,
    surfaceBright: p.surfaceBright,
    surfaceContainerLowest: p.surfaceContainerLowest,
    surfaceContainerLow: p.surfaceContainerLow,
    surfaceContainer: p.surfaceContainer,
    surfaceContainerHigh: p.surfaceContainerHigh,
    surfaceContainerHighest: p.surfaceContainerHighest,
    outline: p.outline,
    outlineVariant: p.outlineVariant,
    inverseSurface: p.inverseSurface,
    onInverseSurface: p.onInverseSurface,
    inversePrimary: p.inversePrimary,
    shadow: p.shadow,
    scrim: p.scrim,
    surfaceTint: p.surfaceTint,
  );

  static ThemeData _build(ForeSeeMePalette p) {
    final scheme = _colorScheme(p);
    final text = ForeSeeMeTypography.textTheme(p);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      // Keep Material's tonal overlay off so surface colours stay exactly as
      // defined in the palette (predictable across elevation).
      applyElevationOverlayColor: false,
      splashFactory: InkSparkle.splashFactory,
      extensions: [ForeSeeMeColors.of(p)],
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: ForeSeeMeElevation.level0,
        scrolledUnderElevation: ForeSeeMeElevation.level0,
        centerTitle: true,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: overlayStyleFor(p),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: p.shadow,
        elevation: ForeSeeMeElevation.level1,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: ForeSeeMeRadius.card,
          side: BorderSide(
            color: p.outlineVariant,
            width: ForeSeeMeBorderWidth.hairline,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: ForeSeeMeElevation.level0,
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.surfaceContainerHighest,
          disabledForegroundColor: p.textDisabled,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: ForeSeeMeRadius.control,
          ),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: ForeSeeMeElevation.level1,
          backgroundColor: p.surface,
          foregroundColor: p.primary,
          shadowColor: p.shadow,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: ForeSeeMeRadius.control,
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: p.outline, width: ForeSeeMeBorderWidth.thin),
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: ForeSeeMeRadius.control,
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: text.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: ForeSeeMeRadius.control,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ForeSeeMeSpacing.xl,
          vertical: ForeSeeMeSpacing.lg,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: p.textTertiary),
        labelStyle: text.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: ForeSeeMeRadius.input,
          borderSide: BorderSide(
            color: p.outline,
            width: ForeSeeMeBorderWidth.hairline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: ForeSeeMeRadius.input,
          borderSide: BorderSide(
            color: p.outline,
            width: ForeSeeMeBorderWidth.hairline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ForeSeeMeRadius.input,
          borderSide: BorderSide(
            color: p.primary,
            width: ForeSeeMeBorderWidth.thick,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: ForeSeeMeRadius.input,
          borderSide: BorderSide(color: p.error, width: ForeSeeMeBorderWidth.thin),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: ForeSeeMeRadius.input,
          borderSide: BorderSide(color: p.error, width: ForeSeeMeBorderWidth.thick),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceContainer,
        side: BorderSide(color: p.outlineVariant, width: ForeSeeMeBorderWidth.hairline),
        labelStyle: text.labelMedium,
        shape: const RoundedRectangleBorder(borderRadius: ForeSeeMeRadius.control),
      ),
      dividerTheme: DividerThemeData(
        space: ForeSeeMeSpacing.xxl,
        thickness: ForeSeeMeBorderWidth.thin,
        color: p.outlineVariant,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: ForeSeeMeRadius.sheet),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: ForeSeeMeRadius.card),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.onInverseSurface),
        actionTextColor: p.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: ForeSeeMeRadius.control),
      ),
      // Text selection: cursor, selection wash, and drag handles all track the
      // brand primary (rather than Material's default blue).
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.28),
        selectionHandleColor: p.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceContainerHighest,
        circularTrackColor: p.surfaceContainerHighest,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: ForeSeeMeElevation.level3,
        shape: const RoundedRectangleBorder(borderRadius: ForeSeeMeRadius.card),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inverseSurface,
          borderRadius: ForeSeeMeRadius.control,
        ),
        textStyle: text.labelMedium?.copyWith(color: p.onInverseSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: ForeSeeMeElevation.level3,
        textStyle: text.bodyMedium?.copyWith(color: p.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: ForeSeeMeRadius.card),
      ),
      iconTheme: IconThemeData(color: p.onSurfaceVariant),
      dividerColor: p.outlineVariant,
    );
  }

  /// System status-bar / navigation-bar overlay for a palette: transparent bars
  /// with icon brightness inverted against the theme so they stay legible. Used
  /// by the app bar, and applied globally at the app root (via an
  /// `AnnotatedRegion`) so screens without an app bar switch too.
  static SystemUiOverlayStyle overlayStyleFor(ForeSeeMePalette p) {
    final iconBrightness = p.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness, // Android
      statusBarBrightness: p.brightness, // iOS
      systemNavigationBarColor: p.background,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: p.background,
    );
  }
}
