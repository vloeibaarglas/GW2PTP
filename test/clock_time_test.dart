import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/util/clock_time.dart';

void main() {
  group('formatClockTime', () {
    test('today renders as 12-hour clock time', () {
      final dt = DateTime.now();
      final h = dt.hour;
      final hour12 = h % 12 == 0 ? 12 : h % 12;
      final mm = dt.minute.toString().padLeft(2, '0');
      final ampm = h < 12 ? 'AM' : 'PM';
      expect(formatClockTime(dt), '$hour12:$mm $ampm');
    });

    test('non-today renders with month/day prefix', () {
      final dt = DateTime.now().subtract(const Duration(days: 2));
      final out = formatClockTime(dt);
      expect(out, startsWith('${dt.month}/${dt.day} '));
      expect(out, contains(RegExp(r'\d{1,2}:\d{2} (AM|PM)$')));
    });

    test('midnight and noon render as 12', () {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 0, 5);
      final noon = DateTime(now.year, now.month, now.day, 12, 5);
      expect(formatClockTime(midnight), '12:05 AM');
      expect(formatClockTime(noon), '12:05 PM');
    });
  });
}
