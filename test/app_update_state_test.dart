import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/state/app_update_state.dart';
import 'package:gw2tp/store/update_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_check_test.dart' show releaseJson;

Future<SharedPreferences> mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateSettings', () {
    test('auto-check defaults off, round-trips', () async {
      final prefs = await mockPrefs();
      final settings = UpdateSettings(prefs);

      expect(settings.autoCheck, isFalse);
      expect(settings.lastCheckAtMs, 0);

      await settings.setAutoCheck(true);
      await settings.setLastCheckAtMs(12345);

      expect(settings.autoCheck, isTrue);
      expect(settings.lastCheckAtMs, 12345);
    });
  });

  group('AppUpdateState', () {
    late SharedPreferences prefs;

    setUp(() async {
      prefs = await mockPrefs();
    });

    AppUpdateState stateWith(MockClient client, {String version = '0.1.0'}) =>
        AppUpdateState(
          prefs: prefs,
          client: client,
          loadCurrentVersion: () async => version,
        );

    test('check finds a newer release and moves the clock', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final state = stateWith(client);

      await state.check();

      expect(state.status, UpdateStatus.available);
      expect(state.latest!.tag, 'v0.1.1');
      expect(state.lastCheckAtMs, greaterThan(0));
    });

    test('check with the same version is up to date', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(releaseJson(tag: 'v0.1.0')), 200));
      final state = stateWith(client);

      await state.check();

      expect(state.status, UpdateStatus.upToDate);
    });

    test('failed check keeps the old clock', () async {
      final client = MockClient((_) async => http.Response('no', 500));
      final state = stateWith(client);
      await state.settings.setLastCheckAtMs(12345);

      await state.check();

      expect(state.status, UpdateStatus.failed);
      expect(state.error, contains('500'));
      expect(state.lastCheckAtMs, 12345);
    });

    test('maybeAutoCheck is a no-op when the toggle is off', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(jsonEncode(releaseJson()), 200);
      });
      final state = stateWith(client);

      await state.maybeAutoCheck();

      expect(calls, 0);
      expect(state.status, UpdateStatus.idle);
    });

    test('maybeAutoCheck skips when a check ran within 3 days', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(jsonEncode(releaseJson()), 200);
      });
      final state = stateWith(client);
      await state.settings.setAutoCheck(true);
      await state.settings.setLastCheckAtMs(
        DateTime.now().millisecondsSinceEpoch - const Duration(days: 1).inMilliseconds,
      );

      await state.maybeAutoCheck();

      expect(calls, 0);
    });

    test('maybeAutoCheck runs when the last check is over 3 days old',
        () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final state = stateWith(client);
      await state.settings.setAutoCheck(true);
      await state.settings.setLastCheckAtMs(
        DateTime.now().millisecondsSinceEpoch - const Duration(days: 4).inMilliseconds,
      );

      await state.maybeAutoCheck();

      expect(state.status, UpdateStatus.available);
    });

    test('install downloads, verifies SHA-256, hands to installer',
        () async {
      final apkBytes = utf8.encode('fake-apk-bytes');
      final sha = sha256.convert(apkBytes).toString();
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('api.github.com')) {
          return http.Response(jsonEncode(releaseJson()), 200);
        }
        if (url.endsWith('.sha256')) {
          return http.Response('$sha  gw2-ptp-deadbeef.apk\n', 200);
        }
        return http.Response.bytes(apkBytes, 200);
      });
      String? installedPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.vloeibaarglas.gw2tp/install'),
        (call) async {
          if (call.method == 'installApk') {
            installedPath = (call.arguments as Map)['path'] as String;
            return true;
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.vloeibaarglas.gw2tp/install'),
          null,
        );
      });
      final state = stateWith(client);
      await state.check();
      expect(state.status, UpdateStatus.available);

      final ok = await state.install();

      expect(ok, isTrue);
      expect(state.status, UpdateStatus.handedToInstaller);
      expect(installedPath, endsWith('gw2-ptp-update.apk'));
      final downloaded = File(installedPath!);
      expect(await downloaded.exists(), isTrue);
      await downloaded.delete();
    });

    test('install fails when the SHA-256 does not match', () async {
      final apkBytes = utf8.encode('fake-apk-bytes');
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('api.github.com')) {
          return http.Response(jsonEncode(releaseJson()), 200);
        }
        if (url.endsWith('.sha256')) {
          return http.Response("${'b' * 64}  gw2-ptp-deadbeef.apk\n", 200);
        }
        return http.Response.bytes(apkBytes, 200);
      });
      final state = stateWith(client);
      await state.check();

      final ok = await state.install();

      expect(ok, isFalse);
      expect(state.status, UpdateStatus.failed);
      expect(state.error, contains('SHA-256'));
    });
  });
}
