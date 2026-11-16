/// App-update preferences, persisted in SharedPreferences.
///
/// Nothing here installs anything: the auto-check only *finds* a release.
/// Installing always starts from the user's tap in the update sheet, and
/// Android asks them to confirm the install.
library;

import 'package:shared_preferences/shared_preferences.dart';

class UpdateSettings {
  static const _autoCheckKey = 'update_auto_check';
  static const _lastCheckKey = 'update_last_check_ms';
  static const _knownLatestKey = 'update_known_latest_tag';
  static const _dismissedKey = 'update_dismissed_tag';

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

  /// Tag of the newest release seen, '' when none checked yet.
  String get knownLatestTag => _prefs.getString(_knownLatestKey) ?? '';

  Future<void> setKnownLatestTag(String tag) =>
      _prefs.setString(_knownLatestKey, tag);

  /// Tag the user tapped Later on. The top-right button stops badging
  /// for that tag (the update is still shown when the sheet opens).
  String get dismissedTag => _prefs.getString(_dismissedKey) ?? '';

  Future<void> setDismissedTag(String tag) =>
      _prefs.setString(_dismissedKey, tag);
}
