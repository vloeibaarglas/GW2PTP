import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/util/app_version.dart';

void main() {
  group('compareVersions', () {
    test('equal versions compare 0, with or without v and parts', () {
      expect(compareVersions('0.1.0', '0.1.0'), 0);
      expect(compareVersions('v0.1.1', '0.1.1'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('v1.0', '1.0.0'), 0);
    });

    test('newer patch/minor/major compare 1', () {
      expect(compareVersions('0.1.1', '0.1.0'), 1);
      expect(compareVersions('0.2.0', '0.1.9'), 1);
      expect(compareVersions('1.0.0', '0.9.9'), 1);
      expect(compareVersions('v0.1.10', '0.1.9'), 1);
    });

    test('older versions compare -1', () {
      expect(compareVersions('0.1.0', '0.1.1'), -1);
      expect(compareVersions('0.1.9', '0.2.0'), -1);
    });

    test('numeric parts, not lexicographic', () {
      expect(compareVersions('0.1.10', '0.1.9'), 1);
      expect(compareVersions('0.1.9', '0.1.10'), -1);
    });
  });

  group('isNewerVersion', () {
    test('release tag newer than installed', () {
      expect(isNewerVersion('0.1.1', '0.1.0'), isTrue);
      expect(isNewerVersion('v0.1.1', '0.1.0'), isTrue);
    });

    test('same or older is not newer', () {
      expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
      expect(isNewerVersion('0.1.0', '0.1.1'), isFalse);
    });
  });
}
