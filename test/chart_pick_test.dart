import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/ui/screens/item_detail_screen.dart';

void main() {
  // Plot geometry in the tests: width 360, left pad 48, right pad 8,
  // so the plot runs from x=48 to x=352 (plotW 304).
  const width = 360.0;

  group('priceChartPickIndex', () {
    test('short history maps the touch across the full range', () {
      expect(priceChartPickIndex(48, width, 100), 0);
      expect(priceChartPickIndex(352, width, 100), 99);
      expect(priceChartPickIndex(200, width, 100), 50);
    });

    test('short history clamps outside the plot', () {
      expect(priceChartPickIndex(0, width, 100), 0);
      expect(priceChartPickIndex(500, width, 100), 99);
    });

    test('long history maps against the drawn points, not the full count',
        () {
      // 1520 points downsample to 400 drawn points. A touch a quarter
      // across the plot must pick drawn index ~100, not full index ~380
      // (the old mapping, which the painter then dropped as out of range
      // and the tooltip raced ahead of the finger).
      expect(priceChartPickIndex(124, width, 1520), 100);
      expect(priceChartPickIndex(200, width, 1520), 200);
    });

    test('long history stops at the last drawn point', () {
      expect(priceChartPickIndex(352, width, 1520), 399);
      expect(priceChartPickIndex(500, width, 1520), 399);
      expect(priceChartPickIndex(48, width, 1520), 0);
      expect(priceChartPickIndex(0, width, 1520), 0);
    });

    test('long history never returns an index past the drawn data', () {
      for (var dx = 0.0; dx <= 500; dx += 7) {
        expect(priceChartPickIndex(dx, width, 1520), lessThan(400));
      }
    });

    test('picked point sits on the touch, within half a drawn step', () {
      // Drawn x for index j (400 drawn points over plotW 304).
      double drawnX(int j) => 48 + j / 399 * 304;
      const halfStep = 304 / 399 / 2;
      for (var dx = 48.0; dx <= 352; dx += 7) {
        final i = priceChartPickIndex(dx, width, 1520);
        expect((drawnX(i) - dx).abs(), lessThanOrEqualTo(halfStep + 1));
      }
    });

    test('degenerate counts return 0', () {
      expect(priceChartPickIndex(100, width, 1), 0);
      expect(priceChartPickIndex(100, width, 0), 0);
    });
  });
}
