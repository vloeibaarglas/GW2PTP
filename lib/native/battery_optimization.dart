import 'package:flutter/services.dart';

/// Tiny native bridge replacing the unmaintained `disable_battery_optimization`
/// plugin (its Android build script still calls the long-dead jcenter()).
///
/// Implemented in MainActivity.kt:
/// - `isBatteryOptimizationDisabled` -> PowerManager.isIgnoringBatteryOptimizations
/// - `isBackgroundRestricted` -> ActivityManager.isBackgroundRestricted
/// - `showDisableBatteryOptimizationSettings` -> fires the system exemption prompt
/// - `showAppBatterySettings` -> opens the app info page (one tap from the
///   per-app Battery screen: Unrestricted / Optimized / Restricted)
///
/// Android offers no API to re-enable battery optimization programmatically,
/// so turning it back ON always goes through system settings.
class BatteryOptimization {
  static const MethodChannel _channel =
      MethodChannel('com.vloeibaarglas.gw2tp/battery');

  static Future<bool> get isBatteryOptimizationDisabled async {
    final value = await _channel.invokeMethod<bool>(
      'isBatteryOptimizationDisabled',
    );
    return value ?? false;
  }

  static Future<bool> get isBackgroundRestricted async {
    final value = await _channel.invokeMethod<bool>('isBackgroundRestricted');
    return value ?? false;
  }

  static Future<bool> showDisableBatteryOptimizationSettings() async {
    final value = await _channel.invokeMethod<bool>(
      'showDisableBatteryOptimizationSettings',
    );
    return value ?? false;
  }

  static Future<bool> showAppBatterySettings() async {
    final value = await _channel.invokeMethod<bool>('showAppBatterySettings');
    return value ?? false;
  }
}

/// The three per-app battery modes Android actually has (Samsung's
/// Unrestricted / Optimized / Restricted screen maps onto these).
enum BatteryMode {
  unrestricted,
  optimized,
  restricted,
  unknown,
}

/// Reads the real system state: the doze exemption first, then the
/// background-restriction flag.
Future<BatteryMode> getBatteryMode() async {
  try {
    if (await BatteryOptimization.isBatteryOptimizationDisabled) {
      return BatteryMode.unrestricted;
    }
    if (await BatteryOptimization.isBackgroundRestricted) {
      return BatteryMode.restricted;
    }
    return BatteryMode.optimized;
  } catch (_) {
    return BatteryMode.unknown;
  }
}
