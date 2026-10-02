import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/sync/order_watcher.dart';

Map<String, dynamic> row(int id, int itemId, int qty, int price) => {
      'id': id,
      'item_id': itemId,
      'quantity': qty,
      'price': price,
    };

void main() {
  group('detectFills', () {
    test('returns fills newer than the checkpoint, oldest first', () {
      final history = [
        row(105, 1, 10, 100), // newest
        row(104, 2, 5, 200),
        row(103, 3, 1, 50), // at/below checkpoint
      ];
      final fills = detectFills('buy', history, 103);
      expect(fills.length, 2);
      expect(fills[0].itemId, 2); // oldest first
      expect(fills[1].itemId, 1);
      expect(fills[0].side, 'buy');
      expect(fills[0].total, 5 * 200);
    });

    test('empty when nothing is newer', () {
      expect(detectFills('sell', [row(100, 1, 1, 1)], 100), isEmpty);
    });

    test('skips malformed rows', () {
      final history = [
        {'id': 101}, // no item/qty/price
        row(102, 0, 5, 10), // bad item id
        row(103, 5, 0, 10), // bad quantity
        row(104, 5, 5, 10), // good
      ];
      final fills = detectFills('sell', history, 100);
      expect(fills.length, 1);
      expect(fills[0].itemId, 5);
    });
  });

  group('maxHistoryId', () {
    test('finds the max id', () {
      expect(
        maxHistoryId([row(3, 1, 1, 1), row(9, 1, 1, 1), row(5, 1, 1, 1)]),
        9,
      );
    });

    test('zero for empty history', () {
      expect(maxHistoryId([]), 0);
    });
  });
}
