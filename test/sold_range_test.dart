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

    test('caps at 125 pages / 25,000 transactions', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        // 26,000 rows, 1 minute apart — all inside 30 days.
        historySells: historyRows(
          count: 26000,
          newest: now,
          spacing: const Duration(minutes: 1),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.days(30));
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

    test('a capped fetch narrows instantly; the footer follows coverage',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 26000,
          newest: now,
          spacing: const Duration(minutes: 1),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.days(30));
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isTrue);
      // The tile names this date: the oldest of the 25,000 fetched rows.
      final expectedOldest = now.subtract(const Duration(minutes: 24999));
      expect(
        state.soldHistoryCoveredSince.difference(expectedOldest).abs(),
        lessThan(const Duration(minutes: 2)),
      );
      expect(state.soldHistory.length, 25000);
      final callsAfterWiden = api.historyFetchCalls;

      // Narrow to 1H: instant, no re-fetch. The capped flag stays (the
      // cache IS capped), but the 1H window is fully covered so no footer.
      await state.setSoldRange(HistoryRange.h1);
      expect(api.historyFetchCalls, callsAfterWiden);
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isFalse);
      expect(state.soldHistory.length, lessThan(25000));
    });

    test('narrowing a capped cache to an uncovered window keeps the footer',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 26000,
          newest: now,
          spacing: const Duration(minutes: 1),
        ),
      );
      final state = await makeState(api);
      // 25,000 cached rows span ~17.4 days — the 30d/20d windows reach far
      // beyond coverage, so their totals are identical and the footer must
      // stay to explain why.
      await state.setSoldRange(HistoryRange.days(30));
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isTrue);

      final callsAfterWiden = api.historyFetchCalls;
      await state.setSoldRange(HistoryRange.days(20));
      expect(api.historyFetchCalls, callsAfterWiden);
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isTrue);
      expect(state.soldHistory.length, 25000);
    });

    test('widening beyond a capped cache re-fetches the remainder', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 26000,
          newest: now,
          spacing: const Duration(minutes: 1),
        ),
      );
      final state = await makeState(api);
      await state.setSoldRange(HistoryRange.days(30));
      expect(state.soldHistoryCapped, isTrue);

      await state.setSoldRange(HistoryRange.h1);
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isFalse);
      final callsAfterNarrow = api.historyFetchCalls;

      // The capped cache doesn't cover the full 30d, so widening
      // re-fetches — but the 125-page cap means it re-walks the same
      // pages and finds nothing new; the oldest ~1,000 rows stay beyond
      // reach, which is exactly what the warning tile is for.
      await state.setSoldRange(HistoryRange.days(30));
      expect(api.historyFetchCalls, greaterThan(callsAfterNarrow));
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isTrue);
      expect(state.soldHistory.length, 25000);
    });

    test('greedy widen fetches remaining pages concurrently in batches',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 600,
          newest: now,
          spacing: const Duration(minutes: 10),
        ),
      );
      final state = await makeState(api);
      // Init (24h, sequential): sells page 0 hits the 24h cutoff mid-page,
      // buys page 0 is empty.
      expect(api.historyFetchCalls, 2);

      // Delay only the widen so the init stays fast and deterministic.
      api.historyFetchDelay = const Duration(milliseconds: 20);
      await state.setSoldRange(HistoryRange.d7);
      // Greedy: page 0 re-checked, then pages 1-2 go out as one batch.
      expect(api.historyFetchCalls, 2 + 3);
      expect(api.maxConcurrentHistoryFetches, 2);
      // All 600 rows (a ~100h span) fall inside 7d.
      expect(state.soldHistoryCachedCount, 600);
      expect(state.soldHistoryCachedItems, 1);
      expect(state.soldHistoryCapped, isFalse);
      // The API's 3 pages fit under the cap: full coverage, no truncation.
      expect(state.soldHistoryCoveredSince.millisecondsSinceEpoch, 0);
      expect(state.soldHistoryTruncated, isFalse);
    });

    test('greedy widen throws away the tail past the 25k cap', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final api = FakeGw2Api(
        historySells: historyRows(
          count: 30000,
          newest: now,
          spacing: const Duration(seconds: 3),
        ),
      );
      final state = await makeState(api);
      // Init (24h, sequential): 25,000 rows fit inside 24h, so the walk
      // runs the full 125-page cap (+1 empty buys page).
      expect(api.historyFetchCalls, 125 + 1);
      expect(state.soldHistoryCapped, isTrue);

      await state.setSoldRange(HistoryRange.d7);
      // Greedy re-walks pages 0-124 in batches of 8; the API's pages
      // 125-149 are never requested.
      expect(api.historyFetchCalls, 125 + 1 + 125);
      expect(state.soldHistoryCapped, isTrue);
      expect(state.soldHistoryTruncated, isTrue);
      expect(state.soldHistoryCachedCount, 25000);
    });

    test('soldHistory getter reuses the filtered list across rebuilds', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 240, newest: now),
      );
      final state = await makeState(api);
      // Same instance while the cache and range are unchanged: downstream
      // grouping can memoize on identity.
      expect(identical(state.soldHistory, state.soldHistory), isTrue);
      final before = state.soldHistory;

      // Widening replaces the cache instance, so the view rebuilds.
      await state.setSoldRange(HistoryRange.d7);
      expect(identical(before, state.soldHistory), isFalse);
      expect(identical(state.soldHistory, state.soldHistory), isTrue);

      // Narrowing to a covered window is a pure local filter, but the
      // range changed, so the view rebuilds too.
      await state.setSoldRange(HistoryRange.h1);
      expect(identical(before, state.soldHistory), isFalse);
    });

    test('cache stats getters report counts, items and span', () async {      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 240, newest: now),
      );
      final state = await makeState(api);
      // 24h window: the cutoff lands on page 0, so 24 rows are cached.
      expect(state.soldHistoryCachedCount, 24);
      expect(state.soldHistoryCachedItems, 1);
      final oldest = state.soldHistoryCachedOldest;
      final newest = state.soldHistoryCachedNewest;
      expect(oldest, isNotNull);
      expect(newest, isNotNull);
      expect(newest!.difference(oldest!).inHours, 23);
      // Bought side is empty.
      expect(state.boughtHistoryCachedCount, 0);
      expect(state.boughtHistoryCachedItems, 0);
      expect(state.boughtHistoryCachedOldest, isNull);
      expect(state.boughtHistoryCachedNewest, isNull);
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

  testWidgets('Sold tab shows range buttons and the cap warning tile',
      (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      historySells: historyRows(
        count: 26000,
        newest: now,
        spacing: const Duration(minutes: 1),
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    for (final label in ['1H', '6H', '24H']) {
      expect(find.text(label), findsOneWidget);
    }
    // Day granularity lives behind the dial button (default range is 24H).
    expect(find.text('Days'), findsOneWidget);

    // Widen to 30D via the dial to trigger the capped 25,000-row fetch.
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    await tapDialDay(tester, 30);

    // The warning tile sits directly below the range selector — no
    // scrolling needed to see it.
    // The tile now names the earliest date covered; match on the
    // stable prefix.
    const tilePrefix = 'Showing the 25,000 most recent transactions, back to';
    expect(find.textContaining(tilePrefix), findsOneWidget);

    // Narrow to 1H: the window is fully covered, tile goes away.
    await tester.tap(find.text('1H'));
    await tester.pumpAndSettle();
    expect(find.textContaining(tilePrefix), findsNothing);
  });

  testWidgets('narrowing 30D to 20D on a capped cache keeps the warning',
      (tester) async {
    final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final api = FakeGw2Api(
      // 26,000 rows at 1-minute spacing: the capped 25,000 only span
      // ~17.4 days, so 30D/20D show the same total — the tile must stay
      // visible to explain why.
      historySells: historyRows(
        count: 26000,
        newest: now,
        spacing: const Duration(minutes: 1),
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    await tapDialDay(tester, 30);

    // The tile now names the earliest date covered; match on the
    // stable prefix.
    const tilePrefix = 'Showing the 25,000 most recent transactions, back to';
    expect(find.textContaining(tilePrefix), findsOneWidget);

    // Narrow 30D -> 20D via the dial: instant local filter, tile stays.
    await tester.tap(find.text('30D'));
    await tester.pumpAndSettle();
    await tapDialDay(tester, 20);
    expect(find.textContaining(tilePrefix), findsOneWidget);
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

    test('bought mode survives an AppState restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeGw2Api();

      final first = await makeStateWithPrefs(api, prefs);
      expect(first.boughtMode, BoughtMode.pickup);

      first.setBoughtMode(BoughtMode.history);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final second = await makeStateWithPrefs(api, prefs);
      expect(second.boughtMode, BoughtMode.history);
    });
  });
}
