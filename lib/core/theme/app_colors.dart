import 'package:flutter/material.dart';

class AppColorPalette {
  const AppColorPalette({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.accentVariant,
    required this.background,
    required this.backgroundWarm,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.success,
    required this.successLight,
    required this.error,
    required this.errorLight,
    required this.warning,
    required this.warningLight,
    required this.info,
    required this.infoLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderSoft,
    required this.borderFocus,
  });

  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color accentVariant;
  final Color background;
  final Color backgroundWarm;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color success;
  final Color successLight;
  final Color error;
  final Color errorLight;
  final Color warning;
  final Color warningLight;
  final Color info;
  final Color infoLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderSoft;
  final Color borderFocus;
}

class AppColors {
  AppColors._();

  static const AppColorPalette lightPalette = AppColorPalette(
    primary: Color(0xFF238A17),
    primaryLight: Color(0xFFE8F8E4),
    primaryDark: Color(0xFF17640F),
    accent: Color(0xFF008F86),
    accentVariant: Color(0xFF6750A4),
    background: Color(0xFFF7FAF8),
    backgroundWarm: Color(0xFFF4F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFF4F1),
    surfaceHighest: Color(0xFFE4ECE8),
    success: Color(0xFF238A17),
    successLight: Color(0xFFE7F6E4),
    error: Color(0xFFBA1A1A),
    errorLight: Color(0xFFFFEDEA),
    warning: Color(0xFF9C5E00),
    warningLight: Color(0xFFFFF1D7),
    info: Color(0xFF245EA8),
    infoLight: Color(0xFFE7F0FF),
    textPrimary: Color(0xFF152018),
    textSecondary: Color(0xFF4F5E54),
    textTertiary: Color(0xFF7A857D),
    border: Color(0xFFE0E7E2),
    borderSoft: Color(0xFFF0F4F1),
    borderFocus: Color(0xFF008F86),
  );

  static const AppColorPalette darkPalette = AppColorPalette(
    primary: Color(0xFF49E619),
    primaryLight: Color(0xFF7CFF58),
    primaryDark: Color(0xFF2F9F12),
    accent: Color(0xFF03DAC6),
    accentVariant: Color(0xFF7C4DFF),
    background: Color(0xFF0B0E14),
    backgroundWarm: Color(0xFF14121C),
    surface: Color(0xFF121A14),
    surfaceElevated: Color(0xFF1B2818),
    surfaceHigh: Color(0xFF23283A),
    surfaceHighest: Color(0xFF353A4B),
    success: Color(0xFF49E619),
    successLight: Color(0xFF183B16),
    error: Color(0xFFFF7C78),
    errorLight: Color(0xFF402020),
    warning: Color(0xFFFFB688),
    warningLight: Color(0xFF3F2B1C),
    info: Color(0xFFADC6FF),
    infoLight: Color(0xFF1E2B45),
    textPrimary: Color(0xFFE6E0EE),
    textSecondary: Color(0xFFCACCDA),
    textTertiary: Color(0xFF948EA1),
    border: Color(0x24FFFFFF),
    borderSoft: Color(0x14FFFFFF),
    borderFocus: Color(0xFF03DAC6),
  );

  static AppColorPalette _activePalette = darkPalette;

  static AppColorPalette get activePalette => _activePalette;

  static void useBrightness(Brightness brightness) {
    _activePalette = brightness == Brightness.dark ? darkPalette : lightPalette;
  }

  static Color get primary => _activePalette.primary;
  static Color get primaryLight => _activePalette.primaryLight;
  static Color get primaryDark => _activePalette.primaryDark;
  static Color get accent => _activePalette.accent;
  static Color get accentVariant => _activePalette.accentVariant;
  static Color get background => _activePalette.background;
  static Color get backgroundWarm => _activePalette.backgroundWarm;
  static Color get surface => _activePalette.surface;
  static Color get surfaceElevated => _activePalette.surfaceElevated;
  static Color get surfaceHigh => _activePalette.surfaceHigh;
  static Color get surfaceHighest => _activePalette.surfaceHighest;
  static Color get success => _activePalette.success;
  static Color get successLight => _activePalette.successLight;
  static Color get error => _activePalette.error;
  static Color get errorLight => _activePalette.errorLight;
  static Color get warning => _activePalette.warning;
  static Color get warningLight => _activePalette.warningLight;
  static Color get info => _activePalette.info;
  static Color get infoLight => _activePalette.infoLight;
  static Color get textPrimary => _activePalette.textPrimary;
  static Color get textSecondary => _activePalette.textSecondary;
  static Color get textTertiary => _activePalette.textTertiary;
  static Color get border => _activePalette.border;
  static Color get borderSoft => _activePalette.borderSoft;
  static Color get borderFocus => _activePalette.borderFocus;

  static Color get darkBackground => darkPalette.background;
  static Color get darkSurface => darkPalette.surfaceElevated;
  static Color get darkTextPrimary => darkPalette.textPrimary;
  static Color get darkTextSecondary => darkPalette.textSecondary;

  static const Color adherenceBackground = Color(0xFF0A1628);
  static const Color adherenceSurface = Color(0xFF111F35);
  static const Color adherenceSurfaceHighlight = Color(0xFF1A3050);
  static const Color adherencePrimary = Color(0xFF006D77);
  static const Color adherenceCyan = Color(0xFF28DDE8);
  static const Color adherenceCoral = Color(0xFFFF6B6B);
  static const Color adherenceTextPrimary = Color(0xFFF2FAFB);
  static const Color adherenceTextMuted = Color(0xFF8EA6BD);
  static const Color adherenceOutline = Color(0xFF263C59);
}
