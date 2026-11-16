/// Tiny native bridge for installing a downloaded APK.
///
/// Implemented in MainActivity.kt (channel
/// `com.vloeibaarglas.gw2tp/install`):
/// - `canInstall` -> PackageManager.canRequestPackageInstalls: whether the
///   system will let this app start an install without a detour to
///   system settings first.
/// - `installApk` -> opens the system installer for the APK at [path]
///   via a FileProvider content URI. Android asks the user to confirm;
///   nothing installs silently. Returns false when no installer could
///   be started.
/// - `openInstallSettings` -> opens the per-app "Install unknown apps"
///   system page, for when `canInstall` is false.
library;

import 'package:flutter/services.dart';

class AppInstall {
  static const MethodChannel _channel =
      MethodChannel('com.vloeibaarglas.gw2tp/install');

  static Future<bool> get canInstall async {
    final value = await _channel.invokeMethod<bool>('canInstall');
    return value ?? false;
  }

  static Future<bool> installApk(String path) async {
    final value = await _channel.invokeMethod<bool>(
      'installApk',
      {'path': path},
    );
    return value ?? false;
  }

  static Future<bool> openInstallSettings() async {
    final value = await _channel.invokeMethod<bool>('openInstallSettings');
    return value ?? false;
  }
}
