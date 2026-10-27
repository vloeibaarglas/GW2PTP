/// Sync mode settings, persisted in SharedPreferences.
///
/// Two modes:
/// * passive — data is fetched when the app opens (default). The UI shows
///   the data age and a stale warning when the last sync is old.
/// * active — a foreground service pings the API every [intervalMinutes]
///   (1–60) and posts a notification for every filled buy/sell order.
library;

import 'package:shared_preferences/shared_preferences.dart';

enum SyncMode { passive, active }

class SyncSettings {
  static const _modeKey = 'sync_mode';
  static const _intervalKey = 'sync_interval_minutes';
  static const _cooldownKey = 'refresh_cooldown_minutes';
  static const _notificationsKey = 'sync_notifications_enabled';
  static const _lastSyncKey = 'sync_last_at_ms';
  static const _lastTickKey = 'sync_last_tick_ms';
  static const _lastTickResultKey = 'sync_last_tick_result';

  final SharedPreferences _prefs;

  SyncSettings(this._prefs);

  SyncMode get mode {
    final raw = _prefs.getString(_modeKey);
    return raw == 'active' ? SyncMode.active : SyncMode.passive;
  }

  Future<void> setMode(SyncMode mode) =>
      _prefs.setString(_modeKey, mode == SyncMode.active ? 'active' : 'passive');

  /// Allowed range 1–60 minutes, clamped defensively.
  int get intervalMinutes {
    final v = _prefs.getInt(_intervalKey) ?? 15;
    return v.clamp(1, 60);
  }

  Future<void> setIntervalMinutes(int minutes) =>
      _prefs.setInt(_intervalKey, minutes.clamp(1, 60));

  /// Minimum gap between manual refreshes, 0–60 minutes; 0 disables the
  /// cooldown (every pull refreshes). Defaults to 2.
  int get refreshCooldownMinutes {
    final v = _prefs.getInt(_cooldownKey) ?? 2;
    return v.clamp(0, 60);
  }

  Future<void> setRefreshCooldownMinutes(int minutes) =>
      _prefs.setInt(_cooldownKey, minutes.clamp(0, 60));

  bool get notificationsEnabled => _prefs.getBool(_notificationsKey) ?? true;

  Future<void> setNotificationsEnabled(bool enabled) =>
      _prefs.setBool(_notificationsKey, enabled);

  /// Epoch millis of the last successful sync, 0 when never synced.
  int get lastSyncAtMs => _prefs.getInt(_lastSyncKey) ?? 0;

  Future<void> setLastSyncAtMs(int ms) => _prefs.setInt(_lastSyncKey, ms);

  /// Epoch millis of the last background tick, 0 when none ran yet.
  int get lastTickAtMs => _prefs.getInt(_lastTickKey) ?? 0;

  /// One-line outcome of the last background tick ('ok', 'notified 3
  /// fills', or an error description). Empty when no tick ran yet. The
  /// Settings screen shows this so a dead pipeline is diagnosable instead
  /// of silent.
  String get lastTickResult => _prefs.getString(_lastTickResultKey) ?? '';

  Future<void> setLastTick(int ms, String result) async {
    await _prefs.setInt(_lastTickKey, ms);
    await _prefs.setString(_lastTickResultKey, result);
  }

  /// Last seen history-transaction ids per side, for fill detection.
  int lastHistoryId(String side) => _prefs.getInt('history_last_id_$side') ?? 0;

  Future<void> setLastHistoryId(String side, int id) =>
      _prefs.setInt('history_last_id_$side', id);

  /// Reload from disk — needed when the background isolate wrote values
  /// while the UI was alive.
  Future<void> reload() => _prefs.reload();

  /// History tab view preferences (grouping + range per tab), stored as raw
  /// strings. Parsing lives in AppState, where the enums live.
  String historyViewPref(String key, String fallback) =>
      _prefs.getString('history_view_$key') ?? fallback;

  Future<void> setHistoryViewPref(String key, String value) =>
      _prefs.setString('history_view_$key', value);
}
