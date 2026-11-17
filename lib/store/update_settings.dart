/// App-update preferences, persisted in SharedPreferences.
///
/// Nothing here installs anything: the auto-check only *finds* a release.
/// Installing always starts from the user's tap in the Settings section,
/// and Android asks them to confirm the install.
library;

import 'package:shared_preferences/shared_preferences.dart';

class UpdateSettings {
  static const _autoCheckKey = 'update_auto_check';
  static const _lastCheckKey = 'update_last_check_ms';

  final SharedPreferences _prefs;

  UpdateSettings(this._prefs);

  /// Whether the app checks for updates on open. Off by default: the
  /// user opts in, and the check only runs when it is on.
  bool get autoCheck => _prefs.getBool(_autoCheckKey) ?? false;

  Future<void> setAutoCheck(bool enabled) =>
      _prefs.setBool(_autoCheckKey, enabled);

  /// Epoch millis of the last *successful* check, 0 when never checked.
  /// Failed checks do not move the clock, so a failed auto-check retries
  /// on the next open instead of waiting out the 3-day interval.
  int get lastCheckAtMs => _prefs.getInt(_lastCheckKey) ?? 0;

  Future<void> setLastCheckAtMs(int ms) => _prefs.setInt(_lastCheckKey, ms);
}
