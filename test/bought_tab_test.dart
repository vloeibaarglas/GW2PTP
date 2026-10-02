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

    test('buy history caps at 10 pages / 2000 transactions', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historyBuys: buyHistoryRows(
          count: 2100,
          newest: now,
          spacing: const Duration(minutes: 4),
        ),
      );
      final state = await makeBoughtState(api);
      await state.setBoughtRange(HistoryRange.d7);
      expect(state.boughtHistory.length, 2000);
      expect(state.boughtHistoryCapped, isTrue);
    });
  });

  testWidgets('Bought tab mirrors the Sold interface', (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      // Few rows so the delivery section is in the initial viewport.
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

    // Same Group By + Range interface as Sold.
    expect(find.text('Group By'), findsOneWidget);
    expect(find.text('Range'), findsOneWidget);
    for (final label in ['By Txn', 'By Item', 'By Price']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['1H', '6H', '24H']) {
      expect(find.text(label), findsOneWidget);
    }
    // Day granularity lives behind the dial button (default range is 24H).
    expect(find.text('Days'), findsOneWidget);

    // Delivery box items keep their section below the history.
    expect(find.text('Waiting For Pickup'), findsOneWidget);
    expect(find.text('×3', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Bought tab shows the cap footer and hides it on 1H',
      (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      historyBuys: buyHistoryRows(
        count: 2100,
        newest: now,
        spacing: const Duration(minutes: 4),
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();

    // Widen to 7D via the dial to trigger the capped 2,000-row fetch.
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    await tapDialDay(tester, 7);

    final footer = find.text('Showing 2,000 Most Recent Transactions');
    final listView = find.byType(ListView);
    await tester.dragUntilVisible(
      footer,
      listView,
      const Offset(0, -500),
      maxIteration: 400,
    );
    expect(footer, findsOneWidget);

    // Narrowing to 1H is a covered instant switch — no re-fetch, footer gone.
    final callsBefore = api.historyFetchCalls;
    await tester.dragUntilVisible(
      find.text('1H'),
      listView,
      const Offset(0, 500),
      maxIteration: 400,
    );
    await tester.tap(find.text('1H'));
    await tester.pumpAndSettle();
    expect(footer, findsNothing);
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
