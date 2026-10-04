/// Immutable data models for the GW2 Trading Post companion.
///
/// All parsing is defensive: a single malformed row from the API must never
/// crash the app, so every field has a fallback and lists filter out junk.
library;

/// Static item metadata (name + icon + trade flags + rarity/type).
/// Cached on disk permanently — item metadata does not change.
class ItemMeta {
  final int id;
  final String name;
  final String iconUrl;

  /// True when the item is account-bound on acquire (flags contain
  /// AccountBound): it can never be listed on the Trading Post.
  final bool accountBound;

  /// True when flags contain NoSell: the item cannot be sold at all.
  final bool noSell;

  /// GW2 rarity string, e.g. "Exotic". Empty when unknown.
  final String rarity;

  /// GW2 item type string, e.g. "Weapon". Empty when unknown.
  final String type;

  const ItemMeta({
    required this.id,
    required this.name,
    required this.iconUrl,
    this.accountBound = false,
    this.noSell = false,
    this.rarity = '',
    this.type = '',
  });

  factory ItemMeta.fromJson(Map<String, dynamic> json) {
    final flags = json['flags'];
    final flagSet = flags is List
        ? flags.whereType<String>().toSet()
        : <String>{};
    return ItemMeta(
      id: _asInt(json['id']),
      name: (json['name'] as String?)?.trim() ?? 'Unknown Item',
      iconUrl: (json['icon'] as String?) ?? '',
      accountBound: flagSet.contains('AccountBound'),
      noSell: flagSet.contains('NoSell'),
      rarity: (json['rarity'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'icon': iconUrl,
        'accountBound': accountBound,
        'noSell': noSell,
        'rarity': rarity,
        'type': type,
      };

  /// Placeholder used when metadata has not been fetched yet.
  factory ItemMeta.unknown(int id) =>
      ItemMeta(id: id, name: 'Item $id', iconUrl: '');
}

/// One stack of an item in the account's inventory.
class InventoryEntry {
  final int itemId;
  final int count;
  final String location;

  /// Sub-location shown under the count, e.g. "Bag 2" or "Equipped · Coat".
  final String? detail;

  /// Per-stack binding from the API ("Account", "Character"), null when the
  /// stack is unbound. Bank/materials endpoints do not report it.
  final String? binding;

  const InventoryEntry({
    required this.itemId,
    required this.count,
    required this.location,
    this.detail,
    this.binding,
  });

  /// True when this stack is bound to the account or a character — either
  /// reported by the API on the stack, or inherent to the item.
  bool isBound(ItemMeta meta) =>
      binding == 'Account' ||
      binding == 'Character' ||
      meta.accountBound;

  /// True when the stack can be listed on the Trading Post: not flagged
  /// NoSell and not bound.
  bool isSellable(ItemMeta meta) => !meta.noSell && !isBound(meta);

  Map<String, dynamic> toJson() => {
        'id': itemId,
        'count': count,
        'location': location,
        if (detail != null) 'detail': detail,
        if (binding != null) 'binding': binding,
      };

  factory InventoryEntry.fromJson(Map<String, dynamic> json) {
    return InventoryEntry(
      itemId: _asInt(json['id']),
      count: _asInt(json['count']),
      location: (json['location'] as String?) ?? '',
      detail: json['detail'] as String?,
      binding: json['binding'] as String?,
    );
  }
}

/// The Trading Post delivery box: coins and items waiting for pickup.
class DeliveryBox {
  final int coins;
  final List<InventoryEntry> items;

  const DeliveryBox({required this.coins, required this.items});

  factory DeliveryBox.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <InventoryEntry>[];
    if (rawItems is List) {
      for (final row in rawItems) {
        if (row is Map<String, dynamic>) {
          final id = _asInt(row['id']);
          final count = _asInt(row['count']);
          if (id > 0 && count > 0) {
            items.add(
              InventoryEntry(
                itemId: id,
                count: count,
                location: 'Delivery box',
              ),
            );
          }
        }
      }
    }
    return DeliveryBox(coins: _asInt(json['coins']), items: items);
  }

  /// Cache shape mirrors the API shape, so [DeliveryBox.fromJson] reads it.
  Map<String, dynamic> toJson() => {
        'coins': coins,
        'items': [
          for (final i in items) {'id': i.itemId, 'count': i.count},
        ],
      };
}

/// One open Trading Post order (buy or sell).
class TpOrder {
  final int id;
  final int itemId;
  final int price;
  final int quantity;

  const TpOrder({
    required this.id,
    required this.itemId,
    required this.price,
    required this.quantity,
  });

  factory TpOrder.fromJson(Map<String, dynamic> json) {
    return TpOrder(
      id: _asInt(json['id']),
      itemId: _asInt(json['item_id']),
      price: _asInt(json['price']),
      quantity: _asInt(json['quantity']),
    );
  }

  /// Total value at the listed price: order value (buys) or the ask
  /// (sells). The listed price is the valuation — no market ping needed.
  int get totalValue => price * quantity;

  /// Cache shape mirrors the API shape, so [TpOrder.fromJson] reads it.
  Map<String, dynamic> toJson() => {
        'id': id,
        'item_id': itemId,
        'price': price,
        'quantity': quantity,
      };
}

/// One page of transaction history plus the API's total page count
/// (X-Page-Total header), so callers can fetch the remaining pages
/// greedily instead of walking them one by one. [pageTotal] is -1 when
/// the header is absent.
class HistoryPage {
  final List<Map<String, dynamic>> rows;
  final int pageTotal;

  const HistoryPage(this.rows, this.pageTotal);
}

/// One filled transaction from /v2/commerce/transactions/history.
/// [price] is the per-unit price in copper; [filledAt] prefers `purchased`
/// (when it filled) and falls back to `created` (when it was listed).
class TpTransaction {
  final int id;
  final int itemId;
  final int price;
  final int quantity;
  final DateTime? filledAt;

  const TpTransaction({
    required this.id,
    required this.itemId,
    required this.price,
    required this.quantity,
    required this.filledAt,
  });

  factory TpTransaction.fromJson(Map<String, dynamic> json) {
    DateTime? stamp(String key) {
      final raw = json[key];
      return raw is String ? DateTime.tryParse(raw) : null;
    }

    return TpTransaction(
      id: _asInt(json['id']),
      itemId: _asInt(json['item_id']),
      price: _asInt(json['price']),
      quantity: _asInt(json['quantity']),
      filledAt: stamp('purchased') ?? stamp('created'),
    );
  }

  /// Gross proceeds at the sale price.
  int get totalValue => price * quantity;

  /// Cache shape mirrors the API shape: [TpTransaction.fromJson] prefers
  /// `purchased`, so the fill timestamp round-trips through it.
  Map<String, dynamic> toJson() => {
        'id': id,
        'item_id': itemId,
        'price': price,
        'quantity': quantity,
        'purchased': filledAt?.toIso8601String(),
      };
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
