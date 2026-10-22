import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/store/key_store.dart';
import 'package:gw2tp/sync/background_sync.dart';
import 'package:gw2tp/sync/fill_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gw2_api.dart';
import 'test_helpers.dart';
import 'widget_test.dart' show pumpApp;

/// Builds [count] fake buy-history rows, newest first, spaced [spacing]
/// apart ending at [newest].
List<Map<String, dynamic>> buyHistoryRows({
  required int count,
  required DateTime newest,
  Duration spacing = const Duration(hours: 1),
}) => [
      for (var i = 0; i < count; i++)
        {
          'id': 200000 - i,
          'item_id': 19684,
          'price': 120,
          'quantity': 2,
          'purchased': newest.subtract(spacing * i).toIso8601String(),
        },
    ];

Future<AppState> makeBoughtState(FakeGw2Api api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(
    keys: FakeKeyStore('test-key'),
    api: api,
    prefs: prefs,
    notifier: FakeFillNotifier(),
    syncService: FakeSyncService(),
  );
  await state.init();
  return state;
}

void main() {
  group('bought history state', () {
    test('buy history loads on init with the 24h default', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historyBuys: buyHistoryRows(count: 50, newest: now),
      );
      final state = await makeBoughtState(api);
      expect(state.boughtRange, HistoryRange.h24);
      expect(state.boughtHistory.length, 24);
      expect(state.boughtHistoryCapped, isFalse);
    });

    test('buy history drops rows older than the window', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historyBuys: buyHistoryRows(count: 240, newest: now),
      );
      final state = await makeBoughtState(api);
      // 24 of the 240 hourly rows fall inside the 24-hour window.
      expect(state.boughtHistory.length, 24);
    });

    test('buy history caps at 125 pages / 25,000 transactions', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historyBuys: buyHistoryRows(
          count: 26000,
          newest: now,
          spacing: const Duration(minutes: 1),
        ),
      );
      final state = await makeBoughtState(api);
      await state.setBoughtRange(HistoryRange.days(30));
      expect(state.boughtHistory.length, 25000);
      expect(state.boughtHistoryCapped, isTrue);
    });
  });

  testWidgets('Bought tab splits pickup and history modes', (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      historyBuys: buyHistoryRows(count: 3, newest: now),
      delivery: const DeliveryBox(
        coins: 0,
        items: [
          InventoryEntry(itemId: 100, count: 3, location: 'Delivery box'),
        ],
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();

    // Mode toggle, defaulting to pickup.
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    // Pickup mode: the delivery items show, no history rows.
    expect(find.text('Waiting For Pickup'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('No recent purchases.'), findsNothing);

    // The history controls stay visible but greyed out in pickup mode:
    // tapping the range chip must not open its sheet.
    await tester.tap(find.text('24H'));
    await tester.pumpAndSettle();
    expect(find.text('Time window'), findsNothing);
    expect(find.byKey(const ValueKey('day_dial')), findsNothing);

    // Switch to history mode.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // Same filter interface as Sold: three chips showing current values.
    expect(find.text('By Txn'), findsOneWidget);
    expect(find.text('24H'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);

    // The group sheet lists every option with its one-line explanation.
    await tester.tap(find.text('By Txn'));
    await tester.pumpAndSettle();
    for (final label in ['By Txn', 'By Item', 'By Price']) {
      expect(
        find.widgetWithText(RadioListTile<HistoryGrouping>, label),
        findsOneWidget,
      );
    }
    expect(find.text('Every fill on its own row'), findsOneWidget);
    expect(find.text('One row per item, weighted-average price'),
        findsOneWidget);
    expect(find.text('One row per price point'), findsOneWidget);
    // Re-pick the current value to dismiss the sheet.
    await tester.tap(
        find.widgetWithText(RadioListTile<HistoryGrouping>, 'By Txn'));
    await tester.pumpAndSettle();

    // Bought Value tile parallels the Sold tab's Sold Value tile (no net:
    // buys pay no Trading Post cut).
    expect(find.text('Bought Value'), findsOneWidget);

    // History mode shows the rows; the pickup section is gone.
    expect(find.text('Waiting For Pickup'), findsNothing);
    expect(find.text('×3'), findsNothing);
  });

  testWidgets('Bought tab shows the cap warning tile and hides it on 1H',
      (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      historyBuys: buyHistoryRows(
        count: 26000,
        newest: now,
        spacing: const Duration(minutes: 1),
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();

    // History mode for the range controls.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // Widen to 30D via the dial to trigger the capped 25,000-row fetch.
    // The dial lives behind the time chip's sheet now.
    await tester.tap(find.text('24H'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    await tapDialDay(tester, 30);

    // The warning tile sits directly below the range selector.
    // The tile now names the earliest date covered; match on the
    // stable prefix.
    const tilePrefix = 'Showing the 25,000 most recent transactions, back to';
    expect(find.textContaining(tilePrefix), findsOneWidget);

    // Narrowing to 1H is a covered instant switch — no re-fetch, tile gone.
    // The chip reads 30D after the widen above.
    final callsBefore = api.historyFetchCalls;
    await tester.tap(find.text('30D'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1H'));
    await tester.pumpAndSettle();
    expect(find.textContaining(tilePrefix), findsNothing);
    expect(api.historyFetchCalls, callsBefore);
  });

  testWidgets('tapping a bought row expands and collapses its subtitle',
      (tester) async {
    final api = FakeGw2Api(
      historyBuys: [
        {
          'id': 1,
          'item_id': 19684,
          'price': 120,
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
    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();
    // History mode for the rows.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    Text subtitle() => tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (t) => (t.textSpan?.toPlainText() ?? '').startsWith('×'),
        );

    expect(subtitle().maxLines, 1);

    final row = find.widgetWithText(ListTile, 'Item 19684');
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(subtitle().maxLines, isNull);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(subtitle().maxLines, 1);
  });
}
