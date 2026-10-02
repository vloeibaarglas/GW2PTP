/// Theme preference (light / dark / system), persisted in
/// SharedPreferences. Defaults to system so the app follows the device.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeSettings {
  static const _themeKey = 'theme_mode';

  final SharedPreferences _prefs;

  ThemeSettings(this._prefs);

  ThemeMode get themeMode {
    switch (_prefs.getString(_themeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(
        _themeKey,
        switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
}
