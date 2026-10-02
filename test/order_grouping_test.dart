import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/store/key_store.dart';
import 'package:gw2tp/sync/background_sync.dart';
import 'package:gw2tp/sync/fill_notifier.dart';
import 'package:gw2tp/ui/screens/orders_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gw2_api.dart';

TpOrder _order(int id, int itemId, int price, int quantity) => TpOrder(
      id: id,
      itemId: itemId,
      price: price,
      quantity: quantity,
    );

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
  group('groupOrders', () {
    final orders = [
      _order(1, 100, 150, 10),
      _order(2, 100, 160, 5), // same item, different price
      _order(3, 200, 300, 2),
    ];

    test('by order keeps every order as its own row', () {
      final rows = groupOrders(orders, OrderGrouping.order);
      expect(rows.length, 3);
      expect(rows.map((r) => r.orders), everyElement(1));
      expect(rows[0].price, 150);
      expect(rows[0].total, 1500);
    });

    test('by item collapses to weighted-average price', () {
      final rows = groupOrders(orders, OrderGrouping.item);
      expect(rows.length, 2);
      final mithril = rows.firstWhere((r) => r.itemId == 100);
      expect(mithril.quantity, 15);
      expect(mithril.total, 150 * 10 + 160 * 5);
      expect(mithril.price, (150 * 10 + 160 * 5) ~/ 15);
      expect(mithril.orders, 2);
    });

    test('by price collapses only identical item+price', () {
      final rows = groupOrders(orders, OrderGrouping.price);
      expect(rows.length, 3);
      final doubled = [
        _order(1, 100, 150, 10),
        _order(2, 100, 150, 5),
      ];
      final collapsed = groupOrders(doubled, OrderGrouping.price);
      expect(collapsed.length, 1);
      expect(collapsed.single.quantity, 15);
      expect(collapsed.single.orders, 2);
    });

    test('empty input stays empty', () {
      expect(groupOrders(const [], OrderGrouping.item), isEmpty);
    });
  });

  group('listings grouping persistence', () {
    test('defaults to By Order per side', () async {
      final state = await makeState(FakeGw2Api());
      expect(state.sellingGrouping, OrderGrouping.order);
      expect(state.buyingGrouping, OrderGrouping.order);
    });

    test('choices persist independently per side', () async {
      final state = await makeState(FakeGw2Api());
      state.setSellingGrouping(OrderGrouping.item);
      state.setBuyingGrouping(OrderGrouping.price);
      expect(state.sellingGrouping, OrderGrouping.item);
      expect(state.buyingGrouping, OrderGrouping.price);

      // Raw keys are written…
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getString('history_view_listing_selling_grouping'), 'item');
      expect(
          prefs.getString('history_view_listing_buying_grouping'), 'price');

      // …and a new AppState over the same store restores them.
      final restored = AppState(
        keys: FakeKeyStore('test-key'),
        api: FakeGw2Api(),
        prefs: prefs,
        notifier: FakeFillNotifier(),
        syncService: FakeSyncService(),
      );
      await restored.init();
      expect(restored.sellingGrouping, OrderGrouping.item);
      expect(restored.buyingGrouping, OrderGrouping.price);
    });
  });

  group('tick status store', () {
    test('lastTick defaults to never-ran', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(
        keys: FakeKeyStore('test-key'),
        api: FakeGw2Api(),
        prefs: prefs,
        notifier: FakeFillNotifier(),
        syncService: FakeSyncService(),
      );
      expect(state.settings.lastTickAtMs, 0);
      expect(state.settings.lastTickResult, isEmpty);
      expect(state.lastTickLabel, 'Background check has never run.');
    });

    test('setLastTick round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(
        keys: FakeKeyStore('test-key'),
        api: FakeGw2Api(),
        prefs: prefs,
        notifier: FakeFillNotifier(),
        syncService: FakeSyncService(),
      );
      await state.settings.setLastTick(123456789, 'notified 2 fills');
      expect(state.settings.lastTickAtMs, 123456789);
      expect(state.settings.lastTickResult, 'notified 2 fills');
      expect(state.lastTickLabel, contains('notified 2 fills'));
    });
  });
}
