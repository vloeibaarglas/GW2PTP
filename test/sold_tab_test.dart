import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/ui/screens/held_screen.dart';
import 'package:gw2tp/util/time_ago.dart';

import 'fake_gw2_api.dart';
import 'widget_test.dart' show pumpApp;

/// Plain text of every rich-text widget on screen (coin displays and
/// subtitles render as Text.rich with colored unit spans).
List<String> richTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((t) => t.textSpan != null)
    .map((t) => t.textSpan!.toPlainText())
    .toList();

void main() {
  group('TpTransaction.fromJson', () {
    test('prefers purchased over created', () {
      final t = TpTransaction.fromJson({
        'id': 7,
        'item_id': 19684,
        'price': 150,
        'quantity': 2,
        'created': '2026-09-01T10:00:00Z',
        'purchased': '2026-09-28T10:00:00Z',
      });
      expect(t.id, 7);
      expect(t.itemId, 19684);
      expect(t.totalValue, 300);
      expect(t.filledAt, DateTime.utc(2026, 9, 28, 10));
    });

    test('falls back to created when purchased is absent', () {
      final t = TpTransaction.fromJson({
        'id': 8,
        'item_id': 19684,
        'price': 100,
        'quantity': 1,
        'created': '2026-09-20T10:00:00Z',
      });
      expect(t.filledAt, DateTime.utc(2026, 9, 20, 10));
    });

    test('null filledAt when timestamps are garbage', () {
      final t = TpTransaction.fromJson({
        'id': 9,
        'item_id': 19684,
        'price': 100,
        'quantity': 1,
        'purchased': 'not-a-date',
      });
      expect(t.filledAt, isNull);
    });
  });

  group('timeAgo', () {
    test('null and future are just now', () {
      expect(timeAgo(null), '');
      expect(timeAgo(DateTime.now().add(const Duration(minutes: 1))),
          'Just Now');
    });

    test('minutes, hours, days', () {
      final now = DateTime.now();
      expect(timeAgo(now.subtract(const Duration(minutes: 5))), '5 Min Ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3))), '3 Hr Ago');
      expect(timeAgo(now.subtract(const Duration(days: 1))), '1 Day Ago');
      expect(timeAgo(now.subtract(const Duration(days: 12))), '12 Days Ago');
    });
  });

  testWidgets('Sold tab lists sold transactions with totals and timestamps',
      (tester) async {
    final api = FakeGw2Api(
      historySells: [
        {
          'id': 1,
          'item_id': 19684,
          'price': 150,
          'quantity': 2,
          'purchased': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        },
      ],
      delivery: DeliveryBox(
        coins: 500,
        items: [
          const InventoryEntry(
              itemId: 100, count: 3, location: 'Delivery box'),
        ],
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    // Deliveries tab: same tabbing as Listings.
    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    expect(find.text('Bought'), findsOneWidget);
    expect(find.text('Sold'), findsOneWidget);

    // Bought tab shows the delivery item.
    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();
    expect(find.text('Item 100'), findsOneWidget);

    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    // Header totals: 2 × 150c = 300c listed, net 255c; 500c waiting.
    expect(find.text('Sold Value'), findsOneWidget);
    expect(find.text('Net Value'), findsOneWidget);
    expect(find.text('Coins Waiting For Pickup'), findsOneWidget);
    // Coin values render as rich text with colored unit spans.
    final texts = richTexts(tester);
    expect(texts, contains('3s'));
    expect(texts, contains('2s 55c'));
    expect(texts, contains('5s'));
    // The sold listing itself, with a relative timestamp.
    expect(find.text('Item 19684'), findsOneWidget);
    expect(find.textContaining('2 Hr Ago'), findsOneWidget);
  });

  group('groupHistory', () {
    TpTransaction txn({
      required int id,
      required int item,
      required int price,
      required int qty,
    }) =>
        TpTransaction.fromJson({
          'id': id,
          'item_id': item,
          'price': price,
          'quantity': qty,
          'purchased': '2026-09-29T12:00:00Z',
        });

    final history = [
      txn(id: 1, item: 100, price: 150, qty: 2),
      txn(id: 2, item: 100, price: 150, qty: 1),
      txn(id: 3, item: 100, price: 200, qty: 1),
      txn(id: 4, item: 200, price: 50, qty: 4),
    ];

    test('txn mode passes every transaction through', () {
      final rows = groupHistory(history, HistoryGrouping.txn);
      expect(rows.length, 4);
      expect(rows.map((r) => r.sales), everyElement(1));
      expect(rows[0].total, 300);
    });

    test('price mode collapses one row per item-price point', () {
      final rows = groupHistory(history, HistoryGrouping.price);
      expect(rows.length, 3);
      // (100 @ 150): qty 3, total 450.
      expect(rows[0].itemId, 100);
      expect(rows[0].price, 150);
      expect(rows[0].quantity, 3);
      expect(rows[0].total, 450);
      expect(rows[0].sales, 2);
      // (100 @ 200) untouched.
      expect(rows[1].price, 200);
      expect(rows[1].quantity, 1);
      // Item 200 keeps first-appearance order.
      expect(rows[2].itemId, 200);
    });

    test('item mode averages price across price points', () {
      final rows = groupHistory(history, HistoryGrouping.item);
      expect(rows.length, 2);
      // Item 100: qty 4, total 650, weighted avg 162 (floor).
      expect(rows[0].itemId, 100);
      expect(rows[0].quantity, 4);
      expect(rows[0].total, 650);
      expect(rows[0].price, 162);
      expect(rows[0].sales, 3);
      expect(rows[1].itemId, 200);
      expect(rows[1].price, 50);
    });
  });

  testWidgets('tapping a sold row expands and collapses its subtitle',
      (tester) async {
    final api = FakeGw2Api(
      historySells: [
        {
          'id': 1,
          'item_id': 19684,
          'price': 150,
          'quantity': 25652,
          'purchased': DateTime.now()
              .subtract(const Duration(hours: 3))
              .toIso8601String(),
        },
      ],
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    // Summary is the default tab now: navigate to Sold first, or the
    // summary's recent-fills rows (same item) would match the finders.
    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    Text subtitle() => tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (t) => (t.textSpan?.toPlainText() ?? '').startsWith('×'),
        );

    // Collapsed: single clipped line.
    expect(subtitle().maxLines, 1);

    // Tap the row -> subtitle expands to full text. (The pickup card is
    // also a ListTile, so target the row by its title.)
    final row = find.widgetWithText(ListTile, 'Item 19684');
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(subtitle().maxLines, isNull);

    // Tap again -> collapses back to one line.
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(subtitle().maxLines, 1);
  });

  group('sortHistory', () {
    HistoryRow row({required int price, DateTime? filledAt}) => HistoryRow(
          itemId: 100,
          quantity: 1,
          price: price,
          total: price,
          filledAt: filledAt,
          sales: 1,
        );

    final t1 = DateTime.utc(2026, 9, 28, 10);
    final t2 = DateTime.utc(2026, 9, 29, 10);
    final t3 = DateTime.utc(2026, 9, 30, 10);

    test('dateDesc puts the latest fill first, nulls last', () {
      final rows = sortHistory(
        [row(price: 1, filledAt: t1), row(price: 2), row(price: 3, filledAt: t3),
         row(price: 4, filledAt: t2)],
        HistorySort.dateDesc,
      );
      expect(rows.map((r) => r.price), [3, 4, 1, 2]);
    });

    test('priceDesc sorts by unit price, highest first', () {
      final rows = sortHistory(
        [row(price: 50), row(price: 200), row(price: 150)],
        HistorySort.priceDesc,
      );
      expect(rows.map((r) => r.price), [200, 150, 50]);
    });

    test('does not mutate the input list', () {
      final rows = [row(price: 50), row(price: 200)];
      sortHistory(rows, HistorySort.priceDesc);
      expect(rows.map((r) => r.price), [50, 200]);
    });
  });
}
