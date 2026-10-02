import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/store/data_cache.dart';
import 'package:gw2tp/store/key_store.dart';
import 'package:gw2tp/sync/background_sync.dart';
import 'package:gw2tp/sync/fill_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gw2_api.dart';

DataSnapshot sampleSnapshot() => DataSnapshot(
      savedAtMs: 1727865600000,
      walletCoins: 123456,
      delivery: const DeliveryBox(coins: 789, items: [
        InventoryEntry(itemId: 19684, count: 5, location: 'Delivery box'),
      ]),
      buys: const [
        TpOrder(id: 1, itemId: 19684, price: 100, quantity: 10),
      ],
      sells: const [
        TpOrder(id: 2, itemId: 19685, price: 200, quantity: 3),
      ],
      soldHistory: [
        TpTransaction(
          id: 10,
          itemId: 19684,
          price: 110,
          quantity: 2,
          filledAt: DateTime.utc(2026, 10, 1, 12),
        ),
      ],
      boughtHistory: [
        TpTransaction(
          id: 11,
          itemId: 19685,
          price: 90,
          quantity: 4,
          filledAt: DateTime.utc(2026, 10, 1, 13),
        ),
      ],
      soldCoveredSinceMs: 1727779200000,
      boughtCoveredSinceMs: 1727779200000,
      soldCapped: false,
      boughtCapped: true,
      soldFetchedAtMs: 1727865600000,
      boughtFetchedAtMs: 1727865600000,
      inventory: const [
        InventoryEntry(
          itemId: 19684,
          count: 250,
          location: 'Bank',
          detail: 'Bag 1',
          binding: 'Account',
        ),
      ],
    );

Future<SharedPreferences> mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  group('DataSnapshot', () {
    test('round-trips through JSON', () {
      final restored = DataSnapshot.fromJson(
        Map<String, dynamic>.from(sampleSnapshot().toJson()),
      )!;
      expect(restored.walletCoins, 123456);
      expect(restored.delivery.coins, 789);
      expect(restored.delivery.items.single.itemId, 19684);
      expect(restored.buys.single.totalValue, 1000);
      expect(restored.sells.single.id, 2);
      expect(
        restored.soldHistory.single.filledAt,
        DateTime.utc(2026, 10, 1, 12),
      );
      expect(restored.boughtHistory.single.quantity, 4);
      expect(restored.soldCoveredSinceMs, 1727779200000);
      expect(restored.soldCapped, isFalse);
      expect(restored.boughtCapped, isTrue);
      final entry = restored.inventory.single;
      expect(entry.detail, 'Bag 1');
      expect(entry.binding, 'Account');
    });

    test('rejects a wrong version', () {
      final json = Map<String, dynamic>.from(sampleSnapshot().toJson())
        ..['v'] = 999;
      expect(DataSnapshot.fromJson(json), isNull);
    });

    test('skips malformed rows instead of failing the snapshot', () {
      final json = Map<String, dynamic>.from(sampleSnapshot().toJson());
      json['buys'] = [
        {'id': 1, 'item_id': 2, 'price': 3, 'quantity': 4},
        'garbage',
        {'nope': true},
      ];
      final restored = DataSnapshot.fromJson(json)!;
      expect(restored.buys.length, 1);
      expect(restored.sells.length, 1);
    });
  });

  group('DataCache', () {
    test('save then load returns the snapshot', () async {
      final prefs = await mockPrefs();
      final cache = DataCache(prefs);
      await cache.save(sampleSnapshot());
      final loaded = await cache.load();
      expect(loaded, isNotNull);
      expect(loaded!.walletCoins, 123456);
      expect(loaded.inventory.single.location, 'Bank');
    });

    test('load returns null when nothing was saved', () async {
      expect(await DataCache(await mockPrefs()).load(), isNull);
    });

    test('load returns null on a corrupt value', () async {
      final prefs = await mockPrefs();
      final cache = DataCache(prefs);
      await cache.save(sampleSnapshot());
      await prefs.setString(DataCache.cacheKey, 'not json {{{');
      expect(await cache.load(), isNull);
    });

    test('clear removes the snapshot', () async {
      final prefs = await mockPrefs();
      final cache = DataCache(prefs);
      await cache.save(sampleSnapshot());
      await cache.clear();
      expect(await cache.load(), isNull);
    });
  });

  group('AppState cache integration', () {
    Future<AppState> makeStateOn(FakeGw2Api api, SharedPreferences prefs) async {
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

    test(
        'a sync persists the snapshot; a later boot restores it even when '
        'the API is down', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      // Same prefs instance = same "device" across both boots.
      final prefs = await mockPrefs();
      final first = await makeStateOn(
        FakeGw2Api(
          walletCoins: 424242,
          sells: const [
            TpOrder(id: 7, itemId: 19684, price: 150, quantity: 6),
          ],
          historySells: [
            {
              'id': 300001,
              'item_id': 19684,
              'price': 140,
              'quantity': 2,
              'purchased': now.toIso8601String(),
            },
          ],
          inventory: const [
            InventoryEntry(itemId: 19684, count: 42, location: 'Bank'),
          ],
        ),
        prefs,
      );
      expect(first.status, LoadStatus.loaded);

      // The successful sync wrote the snapshot.
      final saved = await DataCache(prefs).load();
      expect(saved, isNotNull);
      expect(saved!.walletCoins, 424242);

      // Second boot: the API rejects the key, but the cached data shows.
      final second = await makeStateOn(FakeGw2Api(validKey: false), prefs);
      expect(second.invalidKey, isTrue);
      expect(second.walletCoins, 424242);
      expect(second.sells.single.id, 7);
      expect(second.soldHistory.single.id, 300001);
      expect(second.inventory.single.count, 42);
    });

    test('clearKey drops the disk cache', () async {
      final prefs = await mockPrefs();
      final state = await makeStateOn(FakeGw2Api(walletCoins: 1), prefs);
      expect(await DataCache(prefs).load(), isNotNull);
      await state.clearKey();
      expect(await DataCache(prefs).load(), isNull);
    });
  });
}
