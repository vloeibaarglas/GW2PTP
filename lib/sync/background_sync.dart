/// Active sync mode: a foreground service that pings the GW2 API on a
/// user-chosen interval (1–60 minutes) and posts a notification for every
/// filled buy/sell order.
///
/// The tick runs in a background isolate, so it is fully self-contained:
/// it builds its own API client, key store, and notifier rather than
/// touching the UI isolate's providers.
library;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/gw2_client.dart';
import '../store/item_meta_cache.dart';
import '../store/key_store.dart';
import '../store/sync_settings.dart';
import '../util/clock_time.dart';
import 'fill_notifier.dart';
import 'order_watcher.dart';

/// Entry point for the background isolate. Must stay top-level.
@pragma('vm:entry-point')
void syncTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(SyncTaskHandler());
}

class SyncTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Fire and forget: a tick must never throw out of the handler.
    runSyncTick().catchError((_) {});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// One active-sync tick: check history for fills, notify, and refresh the
/// light dataset (wallet, delivery, open orders). Inventory is only
/// fetched when the app is open — it is the expensive call.
///
/// The outcome (ok / notified N fills / error) is always persisted, so the
/// Settings screen can show whether the pipeline is actually alive. Every
/// failure used to be swallowed silently, which is exactly how "fill
/// notifications stopped working" stays mysterious.
Future<void> runSyncTick() async {
  var outcome = 'ok';
  try {
    final prefs = await SharedPreferences.getInstance();
    final settings = SyncSettings(prefs);
    final apiKey = await SecureKeyStore().readApiKey();
    if (apiKey == null) {
      // Either no key is saved, or the keystore read failed in this
      // isolate — both look identical here, and both mean there is nothing
      // to check. Recorded, not silent.
      outcome = 'no api key';
    } else {
      final api = HttpGw2Api();
      try {
        final notifier = LocalFillNotifier();
        await notifier.init();

        // Fill detection from transaction history (newest-first, one page).
        for (final side in const ['buys', 'sells']) {
          List<Map<String, dynamic>> history;
          try {
            history = (await api.fetchHistory(apiKey, side)).rows;
          } catch (e) {
            outcome = 'history $side failed: ${_shortTickError(e)}';
            continue;
          }
          final lastId = settings.lastHistoryId(side);
          final fills = detectFills(side, history, lastId);
          try {
            if (fills.isNotEmpty && settings.notificationsEnabled) {
              final meta = ItemMetaCache(prefs);
              await meta.warm(
                {for (final f in fills) f.itemId},
                api.fetchItemMeta,
              );
              await notifier.notifyFills(fills, meta.lookup);
              outcome =
                  'notified ${fills.length} fill${fills.length == 1 ? '' : 's'}';
            }
          } catch (e) {
            // A failed notify must not wedge the detector or kill the
            // other side: the high-water mark still advances below, so the
            // same fills don't re-fire on every tick.
            outcome = 'notify $side failed: ${_shortTickError(e)}';
          } finally {
            final maxId = maxHistoryId(history);
            if (maxId > lastId) {
              await settings.setLastHistoryId(side, maxId);
            }
          }
        }

        await settings.setLastSyncAtMs(DateTime.now().millisecondsSinceEpoch);

        try {
          // Keep the interval visible in the ongoing notification: the start
          // text is replaced after the first tick, so re-read it here.
          final minutes = settings.intervalMinutes.clamp(1, 60);
          await FlutterForegroundTask.updateService(
            notificationText: 'Checking orders every $minutes min · '
                'Last check ${formatClockTime(DateTime.now())}',
          );
        } catch (_) {
          // Updating the ongoing notification is cosmetic.
        }
      } finally {
        api.close();
      }
    }
  } catch (e) {
    outcome = 'tick failed: ${_shortTickError(e)}';
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await SyncSettings(prefs)
        .setLastTick(DateTime.now().millisecondsSinceEpoch, outcome);
  } catch (_) {
    // Recording the outcome must never break the tick.
  }
}

String _shortTickError(Object e) {
  final text = e.toString().replaceFirst('Gw2ApiException: ', '');
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

/// Foreground-service lifecycle, abstracted for tests.
abstract class SyncService {
  Future<bool> get isRunning;
  Future<void> start({required int intervalMinutes});
  Future<void> stop();
}

class ForegroundSyncService implements SyncService {
  static const _channelId = 'tp_sync';
  static const _channelName = 'GW2 PTP Sync';

  @override
  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({required int intervalMinutes}) async {
    final minutes = intervalMinutes.clamp(1, 60);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: 'Periodic Trading Post sync.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(minutes * 60 * 1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    if (await FlutterForegroundTask.isRunningService) {
      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure) {
        throw StateError('Could not restart sync service: ${result.error}');
      }
    }
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'GW2 PTP Sync',
      notificationText: 'Checking orders every $minutes min',
      callback: syncTaskEntryPoint,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('Could not start sync service: ${result.error}');
    }
  }

  @override
  Future<void> stop() => FlutterForegroundTask.stopService();
}

/// No-op fake for widget tests.
class FakeSyncService implements SyncService {
  bool running = false;
  int? lastIntervalMinutes;

  @override
  Future<bool> get isRunning async => running;

  @override
  Future<void> start({required int intervalMinutes}) async {
    running = true;
    lastIntervalMinutes = intervalMinutes;
  }

  @override
  Future<void> stop() async {
    running = false;
  }
}
