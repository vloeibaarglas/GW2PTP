import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/update_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> releaseJson({
  String tag = 'v0.1.1',
  List<Map<String, String>>? assets,
}) =>
    {
      'tag_name': tag,
      'body': 'Built from commit abc1234.\n- %h %s',
      'published_at': '2026-11-16T10:00:00Z',
      'assets': assets ??
          [
            {
              'name': 'gw2-ptp-deadbeef.apk',
              'browser_download_url':
                  'https://example.com/gw2-ptp-deadbeef.apk',
            },
            {
              'name': 'gw2-ptp-deadbeef.apk.sha256',
              'browser_download_url':
                  'https://example.com/gw2-ptp-deadbeef.apk.sha256',
            },
          ],
    };

void main() {
  group('UpdateChecker', () {
    test('newer tag is available, with APK and sha URLs', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final checker = UpdateChecker(client: client, currentVersion: '0.1.0');

      final result = await checker.check();

      expect(result.outcome, UpdateCheckOutcome.available);
      expect(result.release!.tag, 'v0.1.1');
      expect(result.release!.version, '0.1.1');
      expect(result.release!.apkUrl,
          'https://example.com/gw2-ptp-deadbeef.apk');
      expect(result.release!.sha256Url,
          'https://example.com/gw2-ptp-deadbeef.apk.sha256');
      expect(result.release!.notes, contains('Built from commit'));
    });

    test('same tag is up to date', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(releaseJson(tag: 'v0.1.0')), 200));
      final checker = UpdateChecker(client: client, currentVersion: '0.1.0');

      final result = await checker.check();

      expect(result.outcome, UpdateCheckOutcome.upToDate);
      expect(result.release!.tag, 'v0.1.0');
    });

    test('release without an APK fails', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson(assets: [])), 200));
      final checker = UpdateChecker(client: client, currentVersion: '0.1.0');

      final result = await checker.check();

      expect(result.outcome, UpdateCheckOutcome.failed);
      expect(result.error, contains('no APK'));
    });

    test('GitHub error fails with the status', () async {
      final client = MockClient((_) async => http.Response('slow down', 403));
      final checker = UpdateChecker(client: client, currentVersion: '0.1.0');

      final result = await checker.check();

      expect(result.outcome, UpdateCheckOutcome.failed);
      expect(result.error, contains('403'));
    });

    test('network throw fails instead of throwing', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final checker = UpdateChecker(client: client, currentVersion: '0.1.0');

      final result = await checker.check();

      expect(result.outcome, UpdateCheckOutcome.failed);
      expect(result.error, contains('Could not reach GitHub'));
    });

    test('fetchExpectedSha256 reads the first token', () async {
      final client = MockClient((_) async => http.Response(
          '${'a' * 64}  gw2-ptp-deadbeef.apk\n', 200));

      expect(
        await UpdateChecker.fetchExpectedSha256(
            client, 'https://example.com/x.sha256'),
        'a' * 64,
      );
    });

    test('fetchExpectedSha256 is null on a bad body', () async {
      final client = MockClient((_) async => http.Response('garbage', 200));

      expect(
        await UpdateChecker.fetchExpectedSha256(
            client, 'https://example.com/x.sha256'),
        isNull,
      );
    });
  });
}
