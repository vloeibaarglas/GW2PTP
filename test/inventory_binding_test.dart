import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';

void main() {
  group('ItemMeta trade flags', () {
    test('parses AccountBound and NoSell from flags', () {
      final meta = ItemMeta.fromJson({
        'id': 1,
        'name': 'Bound Thing',
        'icon': '',
        'flags': ['AccountBound', 'NoSell'],
      });
      expect(meta.accountBound, isTrue);
      expect(meta.noSell, isTrue);
    });

    test('defaults to sellable when flags are absent', () {
      final meta = ItemMeta.fromJson({'id': 2, 'name': 'Free Thing'});
      expect(meta.accountBound, isFalse);
      expect(meta.noSell, isFalse);
    });

    test('flags round-trip through the disk cache JSON', () {
      final meta = ItemMeta.fromJson({
        'id': 3,
        'name': 'Cached Thing',
        'icon': 'https://example.com/icon.png',
        'flags': ['AccountBound'],
      });
      final restored = ItemMeta(
        id: 3,
        name: (meta.toJson()['name'] as String?) ?? '',
        iconUrl: (meta.toJson()['icon'] as String?) ?? '',
        accountBound: (meta.toJson()['accountBound'] as bool?) ?? false,
        noSell: (meta.toJson()['noSell'] as bool?) ?? false,
      );
      expect(restored.accountBound, isTrue);
      expect(restored.noSell, isFalse);
    });
  });

  group('InventoryEntry bound / sellable', () {
    const sellableMeta = ItemMeta(id: 10, name: 'Sellable', iconUrl: '');
    const accountBoundMeta =
        ItemMeta(id: 11, name: 'Bound', iconUrl: '', accountBound: true);
    const noSellMeta =
        ItemMeta(id: 12, name: 'NoSell', iconUrl: '', noSell: true);

    test('API-reported Account binding counts as bound', () {
      const e = InventoryEntry(
          itemId: 10, count: 1, location: 'Bag', binding: 'Account');
      expect(e.isBound(sellableMeta), isTrue);
      expect(e.isSellable(sellableMeta), isFalse);
    });

    test('API-reported Character binding counts as bound', () {
      const e = InventoryEntry(
          itemId: 10, count: 1, location: 'Bag', binding: 'Character');
      expect(e.isBound(sellableMeta), isTrue);
      expect(e.isSellable(sellableMeta), isFalse);
    });

    test('inherent AccountBound flag counts as bound without stack binding',
        () {
      const e = InventoryEntry(itemId: 11, count: 1, location: 'Bank');
      expect(e.isBound(accountBoundMeta), isTrue);
      expect(e.isSellable(accountBoundMeta), isFalse);
    });

    test('NoSell without binding is sellable: NoSell is a vendor flag, '
        'not a TP flag (Quip carries it yet trades on the TP)', () {
      const e = InventoryEntry(itemId: 12, count: 1, location: 'Bank');
      expect(e.isBound(noSellMeta), isFalse);
      expect(e.isSellable(noSellMeta), isTrue);
    });

    test('unbound item without NoSell is sellable', () {
      const e = InventoryEntry(itemId: 10, count: 5, location: 'Bank');
      expect(e.isBound(sellableMeta), isFalse);
      expect(e.isSellable(sellableMeta), isTrue);
    });
  });
}
