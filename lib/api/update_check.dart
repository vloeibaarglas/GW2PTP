/// Update check against the public GitHub Releases API.
///
/// The repo is public, so no auth is needed: `GET /releases/latest`
/// returns the newest non-draft, non-prerelease release with its APK
/// (`gw2-ptp-<sha8>.apk`) and `.sha256` assets attached. The check only
/// ever *finds* an update — downloading and installing always start from
/// the user's tap in the update sheet.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/app_version.dart';

/// One published release, with the bits the update sheet needs.
class ReleaseInfo {
  /// Release tag, e.g. 'v0.1.1'.
  final String tag;

  /// Version without the 'v', e.g. '0.1.1'.
  final String version;

  /// Direct download URL of the APK asset.
  final String apkUrl;

  /// Direct download URL of the `.apk.sha256` asset, null when the
  /// release carries none (install then skips hash verification).
  final String? sha256Url;

  /// Release notes body (the commit log the release workflow writes).
  final String notes;

  final DateTime? publishedAt;

  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.apkUrl,
    required this.sha256Url,
    required this.notes,
    required this.publishedAt,
  });
}

enum UpdateCheckOutcome { upToDate, available, failed }

/// Result of one check. [release] is set for up-to-date and available;
/// [error] carries the human-readable reason for failed.
class UpdateCheckResult {
  final UpdateCheckOutcome outcome;
  final ReleaseInfo? release;
  final String? error;

  const UpdateCheckResult({
    required this.outcome,
    this.release,
    this.error,
  });

  bool get isAvailable => outcome == UpdateCheckOutcome.available;
}

/// Reads the latest release from GitHub and compares it with the
/// installed version. The HTTP client is injected so tests can fake it.
class UpdateChecker {
  static const repo = 'vloeibaarglas/GW2PTP';
  static const _latestUrl = 'https://api.github.com/repos/$repo/releases/latest';

  final http.Client _client;

  /// The installed version, e.g. '0.1.0' (from package_info_plus).
  final String currentVersion;

  UpdateChecker({required http.Client client, required this.currentVersion})
      : _client = client;

  Future<UpdateCheckResult> check() async {
    late final http.Response res;
    try {
      res = await _client.get(
        Uri.parse(_latestUrl),
        headers: const {'Accept': 'application/vnd.github+json'},
      );
    } catch (e) {
      return UpdateCheckResult(
        outcome: UpdateCheckOutcome.failed,
        error: 'Could not reach GitHub ($e).',
      );
    }
    if (res.statusCode != 200) {
      return UpdateCheckResult(
        outcome: UpdateCheckOutcome.failed,
        error: 'GitHub returned ${res.statusCode}.',
      );
    }
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (body['tag_name'] as String?) ?? '';
      if (tag.isEmpty) {
        return const UpdateCheckResult(
          outcome: UpdateCheckOutcome.failed,
          error: 'Latest release has no version tag.',
        );
      }
      final assets = (body['assets'] as List?) ?? const [];
      String? apkUrl;
      String? sha256Url;
      for (final asset in assets) {
        final name = (asset as Map<String, dynamic>)['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = url;
        } else if (name.endsWith('.apk.sha256')) {
          sha256Url = url;
        }
      }
      if (apkUrl == null || apkUrl.isEmpty) {
        return const UpdateCheckResult(
          outcome: UpdateCheckOutcome.failed,
          error: 'Latest release has no APK attached.',
        );
      }
      final release = ReleaseInfo(
        tag: tag,
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        apkUrl: apkUrl,
        sha256Url: sha256Url,
        notes: (body['body'] as String?) ?? '',
        publishedAt: body['published_at'] != null
            ? DateTime.tryParse(body['published_at'] as String)
            : null,
      );
      return UpdateCheckResult(
        outcome: isNewerVersion(release.version, currentVersion)
            ? UpdateCheckOutcome.available
            : UpdateCheckOutcome.upToDate,
        release: release,
      );
    } catch (e) {
      return UpdateCheckResult(
        outcome: UpdateCheckOutcome.failed,
        error: 'Could not read the release ($e).',
      );
    }
  }

  /// Expected SHA-256 hex of the APK, from the release's `.sha256` asset
  /// (`<sha>  <filename>`). Null when the asset is missing or unreadable.
  static Future<String?> fetchExpectedSha256(
    http.Client client,
    String sha256Url,
  ) async {
    try {
      final res = await client.get(Uri.parse(sha256Url));
      if (res.statusCode != 200) return null;
      final first = res.body.trim().split(RegExp(r'\s+')).firstOrNull;
      return (first != null && first.length == 64) ? first : null;
    } catch (_) {
      return null;
    }
  }
}
