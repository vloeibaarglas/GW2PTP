/// App-update state: check, auto-check, download, and install.
///
/// The flow is approval-only at every step: the auto-check only *finds* a
/// release (every 3 days, on open, and only when the toggle is on); the
/// APK downloads only after the user taps Install; Android asks them to
/// confirm the install itself.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/update_check.dart';
import '../native/app_install.dart';
import '../store/update_settings.dart';

enum UpdateStatus {
  /// Nothing checked yet.
  idle,

  /// A check is running.
  checking,

  /// Latest release is not newer than the installed version.
  upToDate,

  /// A newer release is available.
  available,

  /// The last check failed (network or unreadable release).
  failed,

  /// APK downloading (see [downloadProgress]).
  downloading,

  /// Download verified; the system installer is open (or failed to open).
  handedToInstaller,
}

class AppUpdateState extends ChangeNotifier {
  /// Auto-check runs at most this often, and only on open.
  static const autoCheckInterval = Duration(days: 3);

  final UpdateSettings settings;
  final http.Client _client;

  /// Loads the installed version (package_info_plus in production).
  /// Injected so tests can pin a version without the platform channel.
  final Future<String> Function() _loadCurrentVersion;

  AppUpdateState({
    required SharedPreferences prefs,
    http.Client? client,
    Future<String> Function()? loadCurrentVersion,
  })  : settings = UpdateSettings(prefs),
        _client = client ?? http.Client(),
        _loadCurrentVersion = loadCurrentVersion ??
            (() async => (await PackageInfo.fromPlatform()).version);

  UpdateStatus status = UpdateStatus.idle;
  ReleaseInfo? latest;
  String? currentVersion;
  String? error;
  double? downloadProgress;

  /// "Last checked" label source; 0 means never checked.
  int get lastCheckAtMs => settings.lastCheckAtMs;

  bool get autoCheck => settings.autoCheck;

  Future<void> setAutoCheck(bool enabled) async {
    await settings.setAutoCheck(enabled);
    notifyListeners();
  }

  /// Loads the installed version for the sheet header. Called once from
  /// main; [check] loads it too as a fallback.
  Future<void> init() async {
    if (currentVersion != null) return;
    try {
      currentVersion = await _loadCurrentVersion();
      notifyListeners();
    } catch (_) {
      // Version stays unknown; the sheet shows that instead of crashing.
    }
  }

  /// Runs a check when auto-check is on and the last successful check is
  /// older than [autoCheckInterval]. No-op otherwise — opening the app
  /// never phones home unless the user opted in and a check is due.
  Future<void> maybeAutoCheck() async {
    if (!settings.autoCheck) return;
    final last = settings.lastCheckAtMs;
    if (last > 0 &&
        DateTime.now().millisecondsSinceEpoch - last <
            autoCheckInterval.inMilliseconds) {
      return;
    }
    await check();
  }

  /// Checks GitHub for the latest release. A successful check moves the
  /// 3-day clock; a failed one does not, so it retries on the next open.
  Future<void> check() async {
    if (status == UpdateStatus.checking ||
        status == UpdateStatus.downloading) {
      return;
    }
    status = UpdateStatus.checking;
    error = null;
    notifyListeners();
    try {
      currentVersion ??= await _loadCurrentVersion();
      final checker = UpdateChecker(
        client: _client,
        currentVersion: currentVersion!,
      );
      final result = await checker.check();
      if (result.outcome == UpdateCheckOutcome.failed) {
        status = UpdateStatus.failed;
        error = result.error ?? 'Check failed.';
      } else {
        latest = result.release;
        await settings.setLastCheckAtMs(
          DateTime.now().millisecondsSinceEpoch,
        );
        status = result.isAvailable
            ? UpdateStatus.available
            : UpdateStatus.upToDate;
      }
    } catch (e) {
      status = UpdateStatus.failed;
      error = 'Check failed ($e).';
    }
    notifyListeners();
  }

  /// Downloads the APK, verifies its SHA-256 against the release's
  /// `.sha256` asset when one exists, then hands it to the system
  /// installer. Returns false (and sets [error]) when anything fails;
  /// the install itself is the user's call in the Android prompt.
  ///
  /// Android 8+ only lets an app start an install after the user grants
  /// it "Install unknown apps" in system settings. That grant is checked
  /// first: without it the PackageInstaller silently drops the install
  /// intent (no prompt, no error), so instead of downloading a 56 MB
  /// APK to nowhere, the system settings page opens and the user is told
  /// to allow it and tap Install again.
  Future<bool> install() async {
    final release = latest;
    if (release == null || status == UpdateStatus.downloading) {
      return false;
    }
    bool allowed;
    try {
      allowed = await AppInstall.canInstall;
    } catch (_) {
      // Channel unavailable (tests without the mock, old builds):
      // proceed as before and let the handoff report the real result.
      allowed = true;
    }
    if (!allowed) {
      try {
        await AppInstall.openInstallSettings();
      } catch (_) {
        // Settings page failed to open; the message below still tells
        // the user what to allow and where.
      }
      status = UpdateStatus.available;
      error = 'Allow this app to install apps in system settings '
          '(“Install unknown apps”), then tap Install update again.';
      notifyListeners();
      return false;
    }
    status = UpdateStatus.downloading;
    downloadProgress = 0;
    error = null;
    notifyListeners();
    // The APK must land in the platform cache dir: the FileProvider
    // serves exactly that dir, and a path outside its root makes the
    // install handoff fail (seen on device as "Could not open the
    // Android installer"). Directory.systemTemp is only the fallback —
    // it is not guaranteed to be under the provider's root.
    var downloadDir = Directory.systemTemp.path;
    try {
      downloadDir = await AppInstall.cacheDir ?? downloadDir;
    } catch (_) {
      // Channel unavailable (tests without the mock, old builds):
      // keep the fallback and let the handoff report the real result.
    }
    try {
      final expectedSha = release.sha256Url != null
          ? await UpdateChecker.fetchExpectedSha256(
              _client,
              release.sha256Url!,
            )
          : null;
      final request = http.Request('GET', Uri.parse(release.apkUrl));
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw 'Download failed (HTTP ${response.statusCode}).';
      }
      final total = response.contentLength ?? -1;
      final file = File('$downloadDir/gw2-ptp-update.apk');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          downloadProgress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      if (expectedSha != null) {
        final actual = sha256.convert(await file.readAsBytes()).toString();
        if (actual != expectedSha) {
          await file.delete();
          throw 'Download failed the SHA-256 check — deleted, not installed.';
        }
      }
      final started = await AppInstall.installApk(file.path);
      downloadProgress = null;
      if (!started) {
        // Previously this still reported handedToInstaller, and the UI
        // never renders the error in that branch — the screen claimed
        // Android would ask while nothing happened. Report the failure.
        status = UpdateStatus.failed;
        error = 'Could not open the Android installer.';
        notifyListeners();
        return false;
      }
      status = UpdateStatus.handedToInstaller;
      notifyListeners();
      return true;
    } catch (e) {
      status = UpdateStatus.failed;
      // The native handoff now throws a PlatformException carrying the
      // real reason (e.g. the APK path is outside the FileProvider
      // root); show that message, not the "PlatformException(...)"
      // wrapper.
      error = e is PlatformException ? (e.message ?? e.toString()) : e.toString();
      downloadProgress = null;
      notifyListeners();
      return false;
    }
  }
}
