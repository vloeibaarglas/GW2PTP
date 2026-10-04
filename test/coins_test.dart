import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/util/coins.dart';

void main() {
  group('formatCoins', () {
    test('zero renders as 0c', () {
      expect(formatCoins(0), '0c');
    });

    test('copper only', () {
      expect(formatCoins(99), '99c');
    });

    test('silver and copper', () {
      expect(formatCoins(134), '1s 34c');
    });

    test('gold silver copper', () {
      expect(formatCoins(123456), '12g 34s 56c');
    });

    test('skips zero parts', () {
      expect(formatCoins(10000), '1g');
      expect(formatCoins(10100), '1g 1s');
    });

    test('negative values', () {
      expect(formatCoins(-150), '-1s 50c');
    });

    test('5-digit gold drops copper', () {
      expect(formatCoins(166696691), '16669g 66s');
    });

    test('6-digit gold drops copper', () {
      expect(formatCoins(9999999999), '999999g 99s');
    });

    test('7-digit gold drops silver too', () {
      expect(formatCoins(12345678912), '1234567g');
    });

    test('boundary: 9999g keeps copper, 10000g drops it', () {
      expect(formatCoins(99999999), '9999g 99s 99c');
      expect(formatCoins(100000000), '10000g');
      expect(formatCoins(100005000), '10000g 50s');
    });

    test('boundary: 999999g keeps silver, 1000000g drops it', () {
      expect(formatCoins(9999999999), '999999g 99s');
      expect(formatCoins(10000000000), '1000000g');
    });
  });

  group('coinParts', () {
    test('splits gold, silver, copper', () {
      expect(coinParts(123456).map((p) => '${p.amount}${p.unit}').toList(),
          ['12g', '34s', '56c']);
    });

    test('omits zero parts, zero renders as 0c', () {
      expect(coinParts(10000).map((p) => '${p.amount}${p.unit}').toList(),
          ['1g']);
      expect(coinParts(0).map((p) => '${p.amount}${p.unit}').toList(), ['0c']);
    });
  });

  group('netOfFees', () {
    test('takes 15% off, rounding down', () {
      expect(netOfFees(100), 85);
      expect(netOfFees(199), 169); // 169.15 floored
      expect(netOfFees(0), 0);
    });
  });

  group('maskApiKey', () {
    test('masks a set key', () {
      expect(maskApiKey('ABCDEF12-3456'), '********');
    });

    test('empty for missing key', () {
      expect(maskApiKey(null), '');
      expect(maskApiKey(''), '');
    });
  });
}
