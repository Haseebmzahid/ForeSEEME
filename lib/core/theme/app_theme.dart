import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppDimensions {
  AppDimensions._();
  static const double paddingHorizontal = 20.0;
  static const double cardRadius = 20.0;
  static const double buttonRadius = 14.0;
  static const double inputRadius = 14.0;
  static const double buttonHeight = 58.0;
}

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 12.0;
  static const double md = 24.0;
  static const double lg = 40.0;
  static const double xl = 64.0;
  static const double xxl = 80.0;
}

class AppGradients {
  AppGradients._();

  static LinearGradient get background {
    final isDark = AppColors.activePalette == AppColors.darkPalette;

    return LinearGradient(
      colors: isDark
          ? const [Color(0xFF0D0D1A), Color(0xFF152111), Color(0xFF1A0A2E)]
          : const [Color(0xFFF7FAF8), Color(0xFFEFF8EB), Color(0xFFF3F1FA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.56, 1.0],
    );
  }

  static LinearGradient get primaryAction => LinearGradient(
    colors: [AppColors.accentVariant, AppColors.accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get clinicalStatus => LinearGradient(
    colors: [AppColors.primary, AppColors.primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get softSurface => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 32,
      spreadRadius: -14,
      offset: const Offset(0, 18),
    ),
    BoxShadow(
      color: AppColors.textPrimary.withValues(alpha: 0.04),
      blurRadius: 18,
      spreadRadius: -12,
      offset: const Offset(0, -2),
    ),
  ];
}

class AppTextStyles {
  // Can be used outside theme where needed
  static TextStyle get heading1 => GoogleFonts.spaceGrotesk(
    fontSize: 32,
    height: 1.12,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );
  static TextStyle get heading2 => GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.22,
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );
  static TextStyle get bodyText => GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.textPrimary,
  );
  static TextStyle get caption => GoogleFonts.manrope(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0.6,
    color: AppColors.textSecondary,
  );
}

class AppTheme {
  static ThemeData get lightTheme => _buildTheme(
    palette: AppColors.lightPalette,
    brightness: Brightness.light,
  );

  static ThemeData get darkTheme =>
      _buildTheme(palette: AppColors.darkPalette, brightness: Brightness.dark);

  static Widget applyColors(BuildContext context, Widget? child) {
    AppColors.useBrightness(Theme.of(context).brightness);
    return child ?? const SizedBox.shrink();
  }

  static ThemeData _buildTheme({
    required AppColorPalette palette,
    required Brightness brightness,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        primary: palette.primary,
        secondary: palette.accent,
        error: palette.error,
        surface: palette.surface,
        onSurface: palette.textPrimary,
        brightness: brightness,
      ),
      textTheme: TextTheme(
        displayLarge: _heading1(palette),
        displayMedium: GoogleFonts.spaceGrotesk(
          fontSize: 28,
          height: 1.16,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
          letterSpacing: 0,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
          letterSpacing: 0,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
          letterSpacing: 0,
        ),
        bodyLarge: _bodyText(palette),
        bodyMedium: GoogleFonts.manrope(
          fontSize: 15,
          height: 1.5,
          color: palette.textSecondary,
        ),
        labelLarge: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: brightness == Brightness.dark ? Colors.white : palette.surface,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surfaceElevated,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.34),
        surfaceTintColor: palette.accent.withValues(alpha: 0.04),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          side: BorderSide(color: palette.borderSoft, width: 0.8),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background.withValues(alpha: 0.88),
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
          letterSpacing: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: palette.primary,
          foregroundColor: brightness == Brightness.dark
              ? Colors.white
              : palette.surface,
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
          textStyle: _bodyText(palette).copyWith(
            fontWeight: FontWeight.w600,
            color: brightness == Brightness.dark
                ? Colors.white
                : palette.surface,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: palette.textPrimary,
          backgroundColor: palette.surfaceElevated.withValues(alpha: 0.5),
          side: BorderSide(color: palette.border, width: 1),
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
          textStyle: _bodyText(palette).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 17,
        ),
        hintStyle: _bodyText(palette).copyWith(color: palette.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: BorderSide(color: palette.border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: BorderSide(color: palette.border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: BorderSide(color: palette.borderFocus, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: BorderSide(color: palette.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: BorderSide(color: palette.error, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 24,
        thickness: 1,
        color: palette.border,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHighest,
        contentTextStyle: _bodyText(palette),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        ),
      ),
    );
  }

  static TextStyle _heading1(AppColorPalette palette) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 32,
        height: 1.12,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
        letterSpacing: 0,
      );

  static TextStyle _bodyText(AppColorPalette palette) => GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: palette.textPrimary,
  );
}
