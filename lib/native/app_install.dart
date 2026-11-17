/// Tiny native bridge for installing a downloaded APK.
///
/// Implemented in MainActivity.kt (channel
/// `com.vloeibaarglas.gw2tp/install`):
/// - `cacheDir` -> the platform cache dir (context.cacheDir). The
///   FileProvider serves exactly this dir, so the downloaded APK must
///   land here — Directory.systemTemp is not guaranteed to be under it,
///   and a path outside the provider's root makes installApk fail.
/// - `canInstall` -> PackageManager.canRequestPackageInstalls: whether the
///   system will let this app start an install without a detour to
///   system settings first.
/// - `installApk` -> opens the system installer for the APK at [path]
///   via a FileProvider content URI. Android asks the user to confirm;
///   nothing installs silently. Returns false when the path is empty;
///   throws a PlatformException carrying the native reason (e.g. the
///   APK path is outside the FileProvider root, no installer activity)
///   when the handoff itself fails — that message is what the UI shows.
/// - `openInstallSettings` -> opens the per-app "Install unknown apps"
///   system page, for when `canInstall` is false.
library;

import 'package:flutter/services.dart';

class AppInstall {
  static const MethodChannel _channel =
      MethodChannel('com.vloeibaarglas.gw2tp/install');

  /// The platform cache dir, or null when the channel has no answer
  /// (tests without the mock, old builds). Callers fall back to
  /// Directory.systemTemp then.
  static Future<String?> get cacheDir async {
    final value = await _channel.invokeMethod<String>('cacheDir');
    return value;
  }

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
