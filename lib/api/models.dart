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

  /// True when flags contain NoSell: the item cannot be sold to a vendor
  /// (merchant). This says nothing about the Trading Post — legendaries
  /// like Quip carry NoSell yet trade heavily there — so it never gates
  /// sellability below.
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

  /// True when the stack can be listed on the Trading Post: not bound.
  /// NoSell deliberately does not gate this — it is a vendor flag, and
  /// the inventory screen has no market data to override it with (the
  /// web app's has-price override does not apply here). An unbound stack
  /// of a market-less item reads sellable; that edge is accepted.
  bool isSellable(ItemMeta meta) => !isBound(meta);

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

/// Top-of-book quote from /v2/commerce/prices/:id (public, no key).
/// Null when the item is not listed on the Trading Post.
class CommerceQuote {
  final int buyPrice;
  final int buyQuantity;
  final int sellPrice;
  final int sellQuantity;

  const CommerceQuote({
    required this.buyPrice,
    required this.buyQuantity,
    required this.sellPrice,
    required this.sellQuantity,
  });

  factory CommerceQuote.fromJson(Map<String, dynamic> json) {
    int side(String key, String field) {
      final s = json[key];
      if (s is Map<String, dynamic>) return _asInt(s[field]);
      return 0;
    }

    return CommerceQuote(
      buyPrice: side('buys', 'unit_price'),
      buyQuantity: side('buys', 'quantity'),
      sellPrice: side('sells', 'unit_price'),
      sellQuantity: side('sells', 'quantity'),
    );
  }

  /// Ask minus bid, in copper.
  int get spread => sellPrice - buyPrice;

  /// What one unit nets when bought at the bid and sold into the ask
  /// after the 15% Trading Post fee. Negative for fee-negative books.
  int get flipMargin => (sellPrice * 0.85).round() - buyPrice;
}

/// One price level of the order book.
class ListingLevel {
  final int unitPrice;
  final int quantity;
  final int listings;

  const ListingLevel({
    required this.unitPrice,
    required this.quantity,
    required this.listings,
  });

  factory ListingLevel.fromJson(Map<String, dynamic> json) => ListingLevel(
        unitPrice: _asInt(json['unit_price']),
        quantity: _asInt(json['quantity']),
        listings: _asInt(json['listings']),
      );
}

/// Full order book from /v2/commerce/listings/:id (public, no key).
/// Bids sorted high-to-low, asks low-to-high, as the API returns them.
class ListingBook {
  final List<ListingLevel> bids;
  final List<ListingLevel> asks;

  const ListingBook({required this.bids, required this.asks});

  factory ListingBook.fromJson(Map<String, dynamic> json) {
    List<ListingLevel> levels(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return [
        for (final row in raw)
          if (row is Map<String, dynamic>) ListingLevel.fromJson(row),
      ];
    }

    return ListingBook(bids: levels('buys'), asks: levels('sells'));
  }

  int get levelCount => bids.length + asks.length;
}

/// One gw2bltc history row: [timestamp, sell, buy, sellQty, buyQty, ...].
/// A zero price marks missing data on their side and is dropped.
class PricePoint {
  final DateTime time;
  final int sell;
  final int buy;

  const PricePoint({required this.time, required this.sell, required this.buy});

  static PricePoint? fromRow(List<dynamic> row) {
    if (row.length < 5) return null;
    final t = row[0] is int ? row[0] as int : 0;
    final sell = row[1] is int ? row[1] as int : 0;
    final buy = row[2] is int ? row[2] as int : 0;
    if (t <= 0 || sell <= 0 || buy <= 0) return null;
    return PricePoint(
      time: DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true),
      sell: sell,
      buy: buy,
    );
  }
}

/// One recipe ingredient.
class RecipeIngredient {
  final int itemId;
  final int count;

  const RecipeIngredient({required this.itemId, required this.count});

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) =>
      RecipeIngredient(
        itemId: _asInt(json['item_id']),
        count: _asInt(json['count']),
      );
}

/// A crafting recipe from /v2/recipes/:id (public, no key).
class CraftRecipe {
  final int id;
  final String type;
  final int outputItemId;
  final int outputCount;
  final int minRating;
  final List<String> disciplines;
  final List<RecipeIngredient> ingredients;

  const CraftRecipe({
    required this.id,
    required this.type,
    required this.outputItemId,
    required this.outputCount,
    required this.minRating,
    required this.disciplines,
    required this.ingredients,
  });

  factory CraftRecipe.fromJson(Map<String, dynamic> json) {
    final rawDisc = json['disciplines'];
    final rawIng = json['ingredients'];
    return CraftRecipe(
      id: _asInt(json['id']),
      type: (json['type'] as String?) ?? '',
      outputItemId: _asInt(json['output_item_id']),
      outputCount: _asInt(json['output_item_count']),
      minRating: _asInt(json['min_rating']),
      disciplines: rawDisc is List
          ? [for (final d in rawDisc) if (d is String) d]
          : const [],
      ingredients: rawIng is List
          ? [
              for (final row in rawIng)
                if (row is Map<String, dynamic>)
                  RecipeIngredient.fromJson(row),
            ]
          : const [],
    );
  }
}

/// Full item record from /v2/items/:id (public, no key). The `details`
/// block is type-specific, so it is kept as raw JSON with typed helpers
/// for the fields the details page renders.
class ItemDetail {
  final int id;
  final String name;
  final String description;
  final String type;
  final String rarity;
  final int level;
  final String iconUrl;
  final int vendorValue;
  final String chatLink;
  final Set<String> flags;
  final List<String> restrictions;
  final Map<String, dynamic> details;

  const ItemDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.rarity,
    required this.level,
    required this.iconUrl,
    required this.vendorValue,
    required this.chatLink,
    required this.flags,
    required this.restrictions,
    required this.details,
  });

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['flags'];
    final rawRestrictions = json['restrictions'];
    final rawDetails = json['details'];
    return ItemDetail(
      id: _asInt(json['id']),
      name: ((json['name'] as String?) ?? '').trim(),
      description: ((json['description'] as String?) ?? '').trim(),
      type: (json['type'] as String?) ?? '',
      rarity: (json['rarity'] as String?) ?? '',
      level: _asInt(json['level']),
      iconUrl: (json['icon'] as String?) ?? '',
      vendorValue: _asInt(json['vendor_value']),
      chatLink: (json['chat_link'] as String?) ?? '',
      flags: rawFlags is List
          ? {for (final f in rawFlags) if (f is String) f}
          : const {},
      restrictions: rawRestrictions is List
          ? [for (final r in rawRestrictions) if (r is String) r]
          : const [],
      details: rawDetails is Map<String, dynamic> ? rawDetails : const {},
    );
  }

  bool get accountBound => flags.contains('AccountBound');
  bool get noSell => flags.contains('NoSell');
  bool get soulbindOnUse => flags.contains('SoulBindOnUse');

  /// Short human lines for the type-specific details block, e.g.
  /// weapon power/defense, armor weight class, consumable duration.
  List<String> detailLines() {
    final lines = <String>[];
    String numStr(String key) {
      final v = details[key];
      return v is num ? v.toInt().toString() : '';
    }

    switch (type) {
      case 'Weapon':
        final min = numStr('min_power');
        final max = numStr('max_power');
        if (min.isNotEmpty && max.isNotEmpty) {
          lines.add('Weapon Strength $min - $max');
        }
        final defense = numStr('defense');
        if (defense.isNotEmpty) lines.add('Defense $defense');
        final dtype = details['damage_type'];
        if (dtype is String && dtype.isNotEmpty) lines.add(dtype);
      case 'Armor':
        final defense = numStr('defense');
        if (defense.isNotEmpty) lines.add('Defense $defense');
        final wc = details['weight_class'];
        if (wc is String && wc.isNotEmpty) lines.add(wc);
      case 'Back':
      case 'Trinket':
        final defense = numStr('defense');
        if (defense.isNotEmpty) lines.add('Defense $defense');
      case 'Consumable':
        final durMs = details['duration_ms'];
        if (durMs is num && durMs.toInt() > 0) {
          lines.add('Duration ${(durMs.toInt() / 60000).round()}m');
        }
      case 'Bag':
        final size = numStr('size');
        if (size.isNotEmpty) lines.add('$size Slot Bag');
      case 'Gathering':
      case 'Tool':
        // No extra lines beyond the description.
        break;
    }
    final infix = details['infix_upgrade'];
    if (infix is Map<String, dynamic>) {
      final attrs = infix['attributes'];
      if (attrs is List) {
        for (final a in attrs) {
          if (a is Map<String, dynamic>) {
            final attr = a['attribute'];
            final mod = a['modifier'];
            if (attr is String && mod is num) {
              lines.add('+$mod $attr');
            }
          }
        }
      }
      final buff = infix['buff'];
      if (buff is Map<String, dynamic>) {
        final desc = buff['description'];
        if (desc is String && desc.isNotEmpty) lines.add(desc);
      }
    }
    final slots = details['infusion_slots'];
    if (slots is List && slots.isNotEmpty) {
      lines.add('${slots.length} Infusion Slot${slots.length == 1 ? '' : 's'}');
    }
    return lines;
  }
}
