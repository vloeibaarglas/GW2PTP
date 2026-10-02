/// Local notifications for filled Trading Post orders.
///
/// One notification per fill ("Bought 250× Mithril Ore @ 12c"), with a
/// summary fallback when many fills land in one tick.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/models.dart';
import '../util/coins.dart';
import 'order_watcher.dart';

abstract class FillNotifier {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> notifyFills(List<FillEvent> events, ItemMeta Function(int) meta);
}

class LocalFillNotifier implements FillNotifier {
  static const _channelId = 'order_fills';
  static const _channelName = 'Order Fills';
  static const _maxIndividual = 8;

  /// init() re-creating the channel on every background tick is wasteful;
  /// the plugin/channel setup is idempotent per process.
  static bool _initialized = false;

  /// Rolling notification id so fills from a later tick never silently
  /// replace earlier ones. Masked to 31 bits for Android.
  static int _nextId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final FlutterLocalNotificationsPlugin _plugin;

  LocalFillNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notifications when your Trading Post orders fill.',
      importance: Importance.high,
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Returns null on Android < 13 where no runtime permission exists.
    return await androidImpl?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> notifyFills(
    List<FillEvent> events,
    ItemMeta Function(int) meta,
  ) async {
    if (events.isEmpty) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final shown = events.take(_maxIndividual).toList();
    for (var i = 0; i < shown.length; i++) {
      final e = shown[i];
      final name = meta(e.itemId).name;
      final verb = e.side == 'buy' ? 'Bought' : 'Sold';
      final total = e.side == 'buy'
          ? formatCoins(e.total)
          : '${formatCoins(e.total)} (Net ${formatCoins(netOfFees(e.total))})';
      await _plugin.show(
        _nextId++ & 0x7fffffff,
        '$verb ${e.quantity}× $name',
        '@ ${formatCoins(e.pricePerUnit)} each · $total',
        details,
      );
    }
    final rest = events.length - shown.length;
    if (rest > 0) {
      await _plugin.show(
        _nextId++ & 0x7fffffff,
        'GW2 PTP',
        '+$rest more order fills',
        details,
      );
    }
  }
}

/// Silent fake for tests.
class FakeFillNotifier implements FillNotifier {
  final List<FillEvent> notified = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> notifyFills(
    List<FillEvent> events,
    ItemMeta Function(int) meta,
  ) async {
    notified.addAll(events);
  }
}
