import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/gw2_client.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/store/key_store.dart';
import 'package:gw2tp/sync/background_sync.dart';
import 'package:gw2tp/sync/fill_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gw2_api.dart';
import 'test_helpers.dart';
import 'widget_test.dart' show pumpApp;

/// Builds [count] fake history rows, newest first, spaced [spacing] apart
/// ending at [newest] (offset so no row lands exactly on a window edge).
List<Map<String, dynamic>> historyRows({
  required int count,
  required DateTime newest,
  Duration spacing = const Duration(hours: 1),
}) => [
      for (var i = 0; i < count; i++)
        {
          'id': 100000 - i,
          'item_id': 19684,
          'price': 150,
          'quantity': 1,
          'purchased': newest.subtract(spacing * i).toIso8601String(),
        },
    ];

Future<AppState> makeState(FakeGw2Api api) async {
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
  group('sold history range fetch', () {
    test('default 24h window drops rows older than 24 hours', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 240, newest: now),
      );
      final state = await makeState(api);
      expect(state.soldRange, HistoryRange.h24);
      // 24 of the 240 hourly rows fall inside the 24-hour window.
      expect(state.soldHistory.length, 24);
      expect(state.soldHistoryCapped, isFalse);
    });

    test('setSoldRange widens and narrows the window', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 100, newest: now),
      );
      final state = await makeState(api);
      expect(state.soldRange, HistoryRange.h24);
      expect(state.soldHistory.length, 24);

      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldRange, HistoryRange.d7);
      expect(state.soldHistory.length, 100);
      expect(state.soldHistoryCapped, isFalse);

      await state.setSoldRange(HistoryRange.h1);
      expect(state.soldHistory.length, 1);
    });

    test('caps at 10 pages / 2000 transactions', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        // 2,100 rows, 4 minutes apart — all inside 7 days.
        historySells: historyRows(
          count: 2100,
          newest: now,
          spacing: const Duration(minutes: 4),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldHistory.length,
          AppState.historyMaxPages * Gw2Api.historyPageSize);
      expect(state.soldHistoryCapped, isTrue);
    });

    test('short final page means not capped', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        // 250 rows, 30 minutes apart — all inside 7 days: 200 + 50.
        historySells: historyRows(
          count: 250,
          newest: now,
          spacing: const Duration(minutes: 30),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldHistory.length, 250);
      expect(state.soldHistoryCapped, isFalse);
    });

    test('rows without a usable timestamp are kept', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final rows = historyRows(count: 10, newest: now);
      rows.add({
        'id': 1,
        'item_id': 19684,
        'price': 150,
        'quantity': 1,
        // No purchased/created at all — cannot be range-filtered.
      });
      final api = FakeGw2Api(historySells: rows);
      final state = await makeState(api);
      expect(state.soldHistory.length, 11);
    });
  });

  group('instant range switches', () {
    test('narrowing to a covered window makes no API call', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 100, newest: now),
      );
      final state = await makeState(api);
      expect(state.soldRange, HistoryRange.h24);
      expect(state.soldHistory.length, 24);

      // Widen to 7d: the 24h cache doesn't cover it, so it fetches.
      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldHistory.length, 100);
      final callsAfterWiden = api.historyFetchCalls;
      expect(callsAfterWiden, greaterThan(0));

      // Narrowing to a covered window is a pure local filter — no API call.
      await state.setSoldRange(HistoryRange.h24);
      expect(state.soldRange, HistoryRange.h24);
      expect(api.historyFetchCalls, callsAfterWiden);
      expect(state.soldHistory.length, 24);

      // Widening back out is instant too — the cache still covers 7d.
      await state.setSoldRange(HistoryRange.d7);
      expect(api.historyFetchCalls, callsAfterWiden);
      expect(state.soldHistory.length, 100);
    });

    test('a capped fetch narrows instantly and drops the footer', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 2100,
          newest: now,
          spacing: const Duration(minutes: 4),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldHistoryCapped, isTrue);
      final callsAfterWiden = api.historyFetchCalls;

      await state.setSoldRange(HistoryRange.h1);
      expect(api.historyFetchCalls, callsAfterWiden);
      expect(state.soldHistoryCapped, isFalse);
      expect(state.soldHistory.length, lessThan(2000));
    });

    test('widening back to 7d after a capped fetch re-fetches and restores the footer',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 2100,
          newest: now,
          spacing: const Duration(minutes: 4),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldHistoryCapped, isTrue);

      await state.setSoldRange(HistoryRange.h1);
      expect(state.soldHistoryCapped, isFalse);
      final callsAfterNarrow = api.historyFetchCalls;

      // The capped cache doesn't cover the full 7d, so widening re-fetches.
      await state.setSoldRange(HistoryRange.d7);
      expect(api.historyFetchCalls, greaterThan(callsAfterNarrow));
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistory.length, 2000);
    });

    test('switching beyond the covered window re-fetches', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 100, newest: now),
      );
      final state = await makeState(api);
      final callsAfterInit = api.historyFetchCalls;

      // Pretend the cache only covers the last 12 hours.
      state.soldHistoryCoveredSince =
          DateTime.now().subtract(const Duration(hours: 12));
      await state.setSoldRange(HistoryRange.d3);
      expect(api.historyFetchCalls, greaterThan(callsAfterInit));
    });

    test('a stale cache still filters locally on narrow — never a fetch',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 100, newest: now),
      );
      final state = await makeState(api);
      final callsAfterInit = api.historyFetchCalls;

      // Pretend the cache is far older than any TTL: narrowing must still
      // be a pure local filter.
      state.soldHistoryFetchedAt =
          DateTime.now().subtract(const Duration(hours: 6));
      await state.setSoldRange(HistoryRange.h1);
      expect(api.historyFetchCalls, callsAfterInit);
      expect(state.soldHistory.length, 1);
    });

    test('explicit refresh is incremental: stops at the first known page',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 100, newest: now),
      );
      final state = await makeState(api);
      final callsAfterInit = api.historyFetchCalls;
      expect(state.soldHistory.length, 24);

      // Five new sales land on top (newest first, ids above the old max).
      api.historySells = [
        for (var j = 0; j < 5; j++)
          {
            'id': 100005 - j,
            'item_id': 19684,
            'price': 150,
            'quantity': 1,
            'purchased':
                now.add(Duration(minutes: 30 - 6 * j)).toIso8601String(),
          },
        ...api.historySells,
      ];

      await state.refreshSoldHistory();
      // One page: the 5 new rows, then known rows, then the cutoff ends it.
      // (Without the early stop this would re-walk the full window.)
      expect(api.historyFetchCalls, callsAfterInit + 1);
      expect(state.soldHistory.length, 29);
      final ids = state.soldHistory.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      // Newest first.
      for (var i = 1; i < ids.length; i++) {
        expect(ids[i - 1], greaterThan(ids[i]));
      }
    });

    test('widening reuses cached rows without duplicating them', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 100, newest: now),
      );
      final state = await makeState(api);
      expect(state.soldHistory.length, 24);

      await state.setSoldRange(HistoryRange.d7);
      expect(state.soldHistory.length, 100);
      final ids = state.soldHistory.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('narrowing with an empty cache still loads', () async {
      final api = FakeGw2Api(historySells: []);
      final state = await makeState(api);
      expect(state.soldHistory, isEmpty);
      final callsAfterInit = api.historyFetchCalls;

      // Nothing cached: even a narrow must hit the API rather than show
      // an empty list forever.
      await state.setSoldRange(HistoryRange.h1);
      expect(api.historyFetchCalls, greaterThan(callsAfterInit));
    });

    test('bought range narrows without an API call', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historyBuys: historyRows(count: 200, newest: now),
      );
      final state = await makeState(api);
      expect(state.boughtRange, HistoryRange.h24);
      expect(state.boughtHistory.length, 24);

      // Widen to 7d: needs more data, so it fetches.
      await state.setBoughtRange(HistoryRange.d7);
      expect(state.boughtRange, HistoryRange.d7);
      expect(state.boughtHistory.length, 168);
      final callsAfterWiden = api.historyFetchCalls;

      // Narrow back to 24h: covered by the cache, no API call.
      await state.setBoughtRange(HistoryRange.h24);
      expect(state.boughtRange, HistoryRange.h24);
      expect(api.historyFetchCalls, callsAfterWiden);
      expect(state.boughtHistory.length, 24);
    });
  });

  testWidgets('Sold tab shows range buttons and the capped footer',
      (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      historySells: historyRows(
        count: 2100,
        newest: now,
        spacing: const Duration(minutes: 4),
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    expect(find.text('Range'), findsOneWidget);
    for (final label in ['1H', '6H', '24H']) {
      expect(find.text(label), findsOneWidget);
    }
    // Day granularity lives behind the dial button (default range is 24H).
    expect(find.text('Days'), findsOneWidget);

    // Widen to 7D via the dial to trigger the capped 2,000-row fetch.
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    await tapDialDay(tester, 7);

    // Capped at 2,000: the footer is the last child of the Sold tab's list.
    // The sliver builds rows lazily, so the footer element doesn't exist
    // until it scrolls into view — drag on the ListView itself, not via
    // the footer.
    final footer = find.text('Showing 2,000 Most Recent Transactions');
    final listView = find.byType(ListView);
    await tester.dragUntilVisible(
      footer,
      listView,
      const Offset(0, -500),
      maxIteration: 400,
    );
    expect(footer, findsOneWidget);

    // Scroll back up, then switch to 1H: narrows below the cap and the
    // footer goes away.
    await tester.dragUntilVisible(
      find.text('1H'),
      listView,
      const Offset(0, 500),
      maxIteration: 400,
    );
    await tester.tap(find.text('1H'));
    await tester.pumpAndSettle();
    expect(footer, findsNothing);
  });

  group('history view preferences persist', () {
    Future<AppState> makeStateWithPrefs(
        FakeGw2Api api, SharedPreferences prefs) async {
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

    test('grouping and range survive an AppState restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeGw2Api(historySells: historyRows(count: 10, newest: DateTime.now().toUtc()));

      // Defaults: By Txn, 24h.
      final first = await makeStateWithPrefs(api, prefs);
      expect(first.soldGrouping, HistoryGrouping.txn);
      expect(first.soldRange, HistoryRange.h24);
      expect(first.boughtGrouping, HistoryGrouping.txn);
      expect(first.boughtRange, HistoryRange.h24);

      // Change everything, then restart with the same prefs.
      first.setSoldGrouping(HistoryGrouping.item);
      await first.setSoldRange(HistoryRange.d3);
      first.setBoughtGrouping(HistoryGrouping.price);
      await first.setBoughtRange(HistoryRange.h1);
      // The setters persist without awaiting; let the writes land.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final second = await makeStateWithPrefs(api, prefs);
      expect(second.soldGrouping, HistoryGrouping.item);
      expect(second.soldRange, HistoryRange.d3);
      expect(second.boughtGrouping, HistoryGrouping.price);
      expect(second.boughtRange, HistoryRange.h1);
    });
  });
}
