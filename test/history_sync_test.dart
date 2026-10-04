import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/store/key_store.dart';
import 'package:gw2tp/sync/background_sync.dart';
import 'package:gw2tp/sync/fill_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gw2_api.dart';
import 'sold_range_test.dart' show historyRows, makeState;

AppState _stateOn(FakeGw2Api api, SharedPreferences prefs) => AppState(
      keys: FakeKeyStore('test-key'),
      api: api,
      prefs: prefs,
      notifier: FakeFillNotifier(),
      syncService: FakeSyncService(),
    );

void main() {
  group('history sync concurrency', () {
    test('widening bought then sold runs both syncs (no dropped sync)',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 1500, newest: now),
        historyBuys: historyRows(count: 1500, newest: now),
      );
      api.historyFetchDelay = const Duration(milliseconds: 20);
      final state = await makeState(api);
      final sellsBefore = api.historyFetchCallsBySide['sells']!;
      final buysBefore = api.historyFetchCallsBySide['buys']!;

      // Start the bought widen without awaiting, then widen sold: the old
      // code dropped the second sync because status was already loading.
      // (1500 hourly rows; the 30-day window keeps 720 of them.)
      final boughtWiden = state.setBoughtRange(HistoryRange.days(30));
      await state.setSoldRange(HistoryRange.days(30));
      await boughtWiden;

      expect(api.historyFetchCallsBySide['sells']! - sellsBefore,
          greaterThan(1));
      expect(
          api.historyFetchCallsBySide['buys']! - buysBefore, greaterThan(1));
      expect(state.soldHistoryCachedCount, 720);
      expect(state.boughtHistoryCachedCount, 720);
      expect(state.status, LoadStatus.loaded);
    });

    test('two overlapping sold syncs queue and both complete', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 1500, newest: now),
      );
      api.historyFetchDelay = const Duration(milliseconds: 10);
      final state = await makeState(api);
      // Widen first so the overlapping refreshes walk all 8 pages
      // (1500 rows); the 30-day window keeps 720 of them.
      await state.setSoldRange(HistoryRange.days(30));
      final before = api.historyFetchCallsBySide['sells']!;

      // Each greedy walk fetches 8 pages. Both overlapping requests must
      // run (16 fetches); the old code silently dropped the second.
      final first = state.refreshSoldHistory(stopAtKnown: false);
      final second = state.refreshSoldHistory(stopAtKnown: false);
      await Future.wait([first, second]);

      expect(api.historyFetchCallsBySide['sells']! - before, 16);
      expect(state.soldHistoryCachedCount, 720);
      expect(state.status, LoadStatus.loaded);
    });
  });

  group('history cache persistence', () {
    test('widened rows persist; reopening fetches at most one page per side',
        () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final api = FakeGw2Api(
        historySells: historyRows(count: 1500, newest: now),
        historyBuys: historyRows(count: 1500, newest: now),
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = _stateOn(api, prefs);
      await state.init();
      await state.setSoldRange(HistoryRange.days(30));
      await state.setBoughtRange(HistoryRange.days(30));

      // The widened rows hit disk (previously only refreshAll saved).
      // (1500 hourly rows; the 30-day window keeps 720 of them.)
      final raw = prefs.getString('tp_data_cache_json')!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect((decoded['soldHistory'] as List).length, 720);
      expect((decoded['boughtHistory'] as List).length, 720);

      // Simulate an app restart on the same disk state: the refresh on
      // open must stop at the first fully-known page — one fetch per side.
      final sellsBefore = api.historyFetchCallsBySide['sells']!;
      final buysBefore = api.historyFetchCallsBySide['buys']!;
      final reopened = _stateOn(api, prefs);
      await reopened.init();
      expect(reopened.soldHistoryCachedCount, 720);
      expect(reopened.boughtHistoryCachedCount, 720);
      expect(api.historyFetchCallsBySide['sells']! - sellsBefore,
          lessThanOrEqualTo(1));
      expect(api.historyFetchCallsBySide['buys']! - buysBefore,
          lessThanOrEqualTo(1));
    });
  });
}
