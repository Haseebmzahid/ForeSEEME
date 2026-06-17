import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themePreferenceKey = 'foreseeme_theme_mode';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be provided at startup.');
});

final themeNotifierProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((
  ref,
) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(preferences);
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(this._preferences)
    : super(_themeModeFromName(_preferences.getString(_themePreferenceKey)));

  final SharedPreferences _preferences;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _preferences.setString(_themePreferenceKey, mode.name);
  }

  static ThemeMode _themeModeFromName(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
