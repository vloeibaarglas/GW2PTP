import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/ui/screens/inventory_screen.dart';

ItemMeta _meta({
  int id = 1,
  String rarity = '',
  String type = '',
  bool accountBound = false,
  bool noSell = false,
}) =>
    ItemMeta(
      id: id,
      name: 'Test Item $id',
      iconUrl: '',
      rarity: rarity,
      type: type,
      accountBound: accountBound,
      noSell: noSell,
    );

void main() {
  group('ItemMeta rarity/type', () {
    test('fromJson parses rarity and type', () {
      final meta = ItemMeta.fromJson({
        'id': 81127,
        'name': 'Fire Orchid Blossom',
        'icon': 'https://example.com/icon.png',
        'rarity': 'Fine',
        'type': 'CraftingMaterial',
        'flags': [],
      });
      expect(meta.rarity, 'Fine');
      expect(meta.type, 'CraftingMaterial');
    });

    test('fromJson defaults rarity/type to empty when absent', () {
      final meta = ItemMeta.fromJson({'id': 1, 'name': 'X'});
      expect(meta.rarity, '');
      expect(meta.type, '');
    });

    test('toJson round-trips rarity and type', () {
      final meta = _meta(rarity: 'Exotic', type: 'Weapon');
      final rt = ItemMeta.fromJson({...meta.toJson(), 'id': 1});
      expect(rt.rarity, 'Exotic');
      expect(rt.type, 'Weapon');
    });

    test('unknown() has empty rarity and type', () {
      final meta = ItemMeta.unknown(99);
      expect(meta.rarity, '');
      expect(meta.type, '');
    });
  });

  group('inventoryEntryMatches', () {
    final entries = [
      const InventoryEntry(itemId: 1, count: 5, location: 'Bank'),
      const InventoryEntry(
          itemId: 2, count: 1, location: 'Bank', binding: 'Account'),
      const InventoryEntry(itemId: 3, count: 10, location: 'Bank'),
    ];
    ItemMeta lookup(int id) => switch (id) {
          1 => _meta(id: 1, rarity: 'Exotic', type: 'Weapon'),
          2 => _meta(
              id: 2, rarity: 'Rare', type: 'Armor', accountBound: true),
          3 => _meta(id: 3, rarity: 'Exotic', type: 'Weapon', noSell: true),
          _ => ItemMeta.unknown(id),
        };

    test('no filters matches everything', () {
      for (final e in entries) {
        expect(inventoryEntryMatches(e, lookup), isTrue);
      }
    });

    test('type filter', () {
      expect(
          entries
              .where((e) =>
                  inventoryEntryMatches(e, lookup, typeFilter: 'Weapon'))
              .map((e) => e.itemId),
          [1, 3]);
    });

    test('rarity filter', () {
      expect(
          entries
              .where(
                  (e) => inventoryEntryMatches(e, lookup, rarityFilter: 'Rare'))
              .map((e) => e.itemId),
          [2]);
    });

    test('sellable filter yes', () {
      // 1 is sellable; 2 is bound; 3 is NoSell.
      expect(
          entries
              .where((e) =>
                  inventoryEntryMatches(e, lookup, sellableFilter: true))
              .map((e) => e.itemId),
          [1]);
    });

    test('sellable filter no', () {
      expect(
          entries
              .where((e) =>
                  inventoryEntryMatches(e, lookup, sellableFilter: false))
              .map((e) => e.itemId)
              .toSet(),
          {2, 3});
    });

    test('bound filter yes', () {
      expect(
          entries
              .where(
                  (e) => inventoryEntryMatches(e, lookup, boundFilter: true))
              .map((e) => e.itemId),
          [2]);
    });

    test('bound filter no', () {
      expect(
          entries
              .where(
                  (e) => inventoryEntryMatches(e, lookup, boundFilter: false))
              .map((e) => e.itemId)
              .toSet(),
          {1, 3});
    });

    test('combined filters', () {
      expect(
          entries
              .where((e) => inventoryEntryMatches(
                    e,
                    lookup,
                    typeFilter: 'Weapon',
                    rarityFilter: 'Exotic',
                    sellableFilter: false,
                  ))
              .map((e) => e.itemId),
          [3]);
    });

    test('query still applies alongside filters', () {
      ItemMeta namedLookup(int id) => _meta(id: id).copyWithName('Fire Orchid');
      const e = InventoryEntry(itemId: 9, count: 1, location: 'Bank');
      // Name matches but type does not.
      expect(
          inventoryEntryMatches(e, namedLookup,
              query: 'orchid', typeFilter: 'Weapon'),
          isFalse);
      // Both match (empty type on the item, no type filter).
      expect(
          inventoryEntryMatches(e, namedLookup, query: 'orchid'),
          isTrue);
      // Query does not match.
      expect(
          inventoryEntryMatches(e, namedLookup, query: 'blossom'),
          isFalse);
    });
  });
}

extension on ItemMeta {
  ItemMeta copyWithName(String name) => ItemMeta(
        id: id,
        name: name,
        iconUrl: iconUrl,
        rarity: rarity,
        type: type,
        accountBound: accountBound,
        noSell: noSell,
      );
}
