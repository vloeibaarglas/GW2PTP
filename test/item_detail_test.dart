import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/gw2_client.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/store/item_detail_cache.dart';

import 'fake_gw2_api.dart';

Map<String, dynamic> detailBody(int id) => {
      'id': id,
      'name': 'Test Item $id',
      'description': 'A test item',
      'type': 'Trophy',
      'level': 0,
      'rarity': 'Exotic',
      'vendor_value': 100,
      'chat_link': '[&AgE\$]',
      'icon': 'https://example.com/icon.png',
      'flags': [],
      'restrictions': [],
      'details': {},
    };

void main() {
  group('ItemDetailCache', () {
    test('caches phase-1 bundle inside the TTL: one fetch per id', () async {
      final api = FakeGw2Api()
        ..itemDetails = {7: detailBody(7)}
        ..quotes = {
          7: const CommerceQuote(
            buyPrice: 100,
            buyQuantity: 5,
            sellPrice: 120,
            sellQuantity: 6,
          ),
        };
      final cache = ItemDetailCache();

      final first = await cache.get(7, api);
      final second = await cache.get(7, api);

      expect(identical(first, second), isTrue);
      expect(api.fetchItemDetailCalls, 1);
      expect(api.fetchCommercePricesCalls, 1);
      expect(first.detail.name, 'Test Item 7');
      expect(first.quote!.spread, 20);
    });

    test('concurrent opens share one in-flight fetch', () async {
      final api = FakeGw2Api()..itemDetails = {9: detailBody(9)};
      final cache = ItemDetailCache();
      final results = await Future.wait([
        cache.get(9, api),
        cache.get(9, api),
        cache.get(9, api),
      ]);
      expect(api.fetchItemDetailCalls, 1);
      expect(results.every((b) => identical(b, results.first)), isTrue);
    });

    test('book and history ride the same entry without refetching phase 1',
        () async {
      final api = FakeGw2Api()
        ..itemDetails = {11: detailBody(11)}
        ..books = {
          11: const ListingBook(bids: [], asks: []),
        }
        ..priceHistory = {
          11: [
            PricePoint(
              time: DateTime.utc(2026, 1, 1),
              sell: 120,
              buy: 100,
            ),
          ],
        };
      final cache = ItemDetailCache();
      await cache.get(11, api);
      await cache.book(11, api);
      await cache.history(11, api);
      // Phase-1 fetched exactly once; book/history once each.
      expect(api.fetchItemDetailCalls, 1);
      expect(api.fetchListingsCalls, 1);
      expect(api.fetchPriceHistoryCalls, 1);
      // Second round is fully cached.
      await cache.book(11, api);
      await cache.history(11, api);
      expect(api.fetchListingsCalls, 1);
      expect(api.fetchPriceHistoryCalls, 1);
    });

    test('book/history without an open entry throws StateError', () async {
      final api = FakeGw2Api();
      final cache = ItemDetailCache();
      expect(() => cache.book(13, api), throwsStateError);
      expect(() => cache.history(13, api), throwsStateError);
    });

    test('phase-1 failure does not poison the cache', () async {
      final api = FakeGw2Api()..failingDetailIds = {15};
      final cache = ItemDetailCache();
      await expectLater(
        cache.get(15, api),
        throwsA(isA<Gw2ApiException>()),
      );
      expect(cache.isFresh(15), isFalse);
      // A later success is stored normally.
      api.failingDetailIds = {};
      api.itemDetails = {15: detailBody(15)};
      final bundle = await cache.get(15, api);
      expect(bundle.detail.id, 15);
      expect(cache.isFresh(15), isTrue);
    });

    test('invalidate forces a refetch', () async {
      final api = FakeGw2Api()..itemDetails = {17: detailBody(17)};
      final cache = ItemDetailCache();
      await cache.get(17, api);
      cache.invalidate(17);
      await cache.get(17, api);
      expect(api.fetchItemDetailCalls, 2);
    });
  });

  group('models', () {
    test('CommerceQuote spread and flip margin', () {
      const q = CommerceQuote(
        buyPrice: 1591,
        buyQuantity: 10,
        sellPrice: 1697,
        sellQuantity: 20,
      );
      expect(q.spread, 106);
      // 1697 * 0.85 = 1442.45 -> 1442; 1442 - 1591 = -149.
      expect(q.flipMargin, -149);
    });

    test('ListingBook parses levels in API order', () {
      final book = ListingBook.fromJson({
        'buys': [
          {'listings': 2, 'unit_price': 100, 'quantity': 5},
        ],
        'sells': [
          {'listings': 1, 'unit_price': 120, 'quantity': 7},
        ],
      });
      expect(book.bids.single.unitPrice, 100);
      expect(book.asks.single.quantity, 7);
      expect(book.levelCount, 2);
    });

    test('PricePoint drops zero-price rows', () {
      expect(PricePoint.fromRow([1700000000, 0, 1500, 1, 2]), isNull);
      expect(PricePoint.fromRow([1700000000, 1600, 1500, 1, 2]), isNotNull);
      expect(PricePoint.fromRow([1, 2]), isNull);
    });

    test('ItemDetail detailLines for a weapon', () {
      final d = ItemDetail.fromJson({
        'id': 1,
        'name': 'Sword',
        'type': 'Weapon',
        'rarity': 'Exotic',
        'level': 80,
        'details': {
          'min_power': 900,
          'max_power': 1100,
          'damage_type': 'Physical',
          'infix_upgrade': {
            'attributes': [
              {'attribute': 'Power', 'modifier': 100},
            ],
          },
          'infusion_slots': [
            {'flags': ['Infusion']},
          ],
        },
      });
      final lines = d.detailLines();
      expect(lines, contains('Weapon Strength 900 - 1100'));
      expect(lines, contains('Physical'));
      expect(lines, contains('+100 Power'));
      expect(lines, contains('1 Infusion Slot'));
    });

    test('CraftRecipe parses ingredients', () {
      final r = CraftRecipe.fromJson({
        'id': 5,
        'type': 'Refinement',
        'output_item_id': 9,
        'output_item_count': 2,
        'min_rating': 400,
        'disciplines': ['Artificer'],
        'ingredients': [
          {'item_id': 1, 'count': 3},
        ],
      });
      expect(r.ingredients.single.count, 3);
      expect(r.disciplines, ['Artificer']);
    });
  });
}
