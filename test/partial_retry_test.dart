import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/state/app_state.dart';

import 'fake_gw2_api.dart';
import 'sold_range_test.dart' show makeState;

void main() {
  group('retry after partial sync', () {
    test('banner-tap retry runs despite the cooldown when a section failed',
        () async {
      final api = FakeGw2Api(walletCoins: 12345)..failWallet = true;
      final state = await makeState(api);
      // Boot refresh ran (forced) and only the wallet section failed.
      expect(api.walletFetchCalls, 1);
      expect(state.sectionNotice, contains('wallet'));
      expect(state.status, LoadStatus.loaded);

      // The endpoint recovers; the user taps "Tap to retry" (plain
      // refreshAll, no force) well inside the 2-minute cooldown.
      api.failWallet = false;
      await state.refreshAll();

      // The retry must actually run, not be swallowed by the cooldown.
      expect(api.walletFetchCalls, 2);
      expect(state.sectionNotice, isNull);
      expect(state.walletCoins, 12345);
    });

    test('healthy cooldown still gates a redundant refresh', () async {
      final api = FakeGw2Api(walletCoins: 12345);
      final state = await makeState(api);
      expect(state.sectionNotice, isNull);
      expect(api.walletFetchCalls, 1);

      await state.refreshAll();

      expect(api.walletFetchCalls, 1);
      expect(state.refreshNotice, 'Already up to date');
    });
  });
}
