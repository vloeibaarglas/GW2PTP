/// Guild Wars 2 API client.
///
/// Only the endpoints the companion needs — all keyed Trading Post / account
/// endpoints plus the public item-metadata endpoint. No market-price calls,
/// no background work: the app fetches on open and on pull-to-refresh only.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thrown when the API rejects the key itself (HTTP 401).
class InvalidApiKeyException implements Exception {
  const InvalidApiKeyException();
}

/// Thrown when the key is valid but lacks the permission for an endpoint
/// (HTTP 403). Extends [Gw2ApiException] so generic catch-alls keep working.
class MissingPermissionException extends Gw2ApiException {
  final String endpoint;
  const MissingPermissionException(this.endpoint)
      : super('Missing permission for $endpoint');
}

/// Thrown for transport-level and unexpected HTTP failures.
class Gw2ApiException implements Exception {
  final String message;
  const Gw2ApiException(this.message);

  @override
  String toString() => 'Gw2ApiException: $message';
}

/// The API surface the app needs. Abstract so widget tests can substitute
/// a fake without touching the network.
abstract class Gw2Api {
  /// Rows per page for paginated transaction endpoints (the API maximum).
  /// Callers paging through history use this to detect the final page.
  static const historyPageSize = 200;

  /// Validates [apiKey] with a cheap keyed call and returns the permissions
  /// granted to it. Throws [InvalidApiKeyException] when the key is rejected.
  Future<List<String>> fetchTokenPermissions(String apiKey);

  /// Coins in the wallet (currency id 1), in copper.
  Future<int> fetchWalletCoins(String apiKey);

  /// Coins and items waiting in the delivery box.
  Future<DeliveryBox> fetchDelivery(String apiKey);

  /// Open orders. [side] is 'buys' or 'sells'.
  Future<List<TpOrder>> fetchCurrentOrders(String apiKey, String side);

  /// Recent transaction history, newest first. [side] is 'buys' or 'sells'.
  /// Returns raw rows ({id, item_id, price, quantity, ...}) plus the API's
  /// total page count, so wide fetches can grab pages concurrently.
  Future<HistoryPage> fetchHistory(
    String apiKey,
    String side, {
    int page,
  });

  /// Every item stack across bank, materials, shared inventory slots,
  /// all character bags, and equipped gear.
  Future<List<InventoryEntry>> fetchInventory(String apiKey);

  /// Static metadata (name, icon) for [ids]. Public endpoint, no key.
  Future<Map<int, ItemMeta>> fetchItemMeta(List<int> ids);
}

class HttpGw2Api implements Gw2Api {
  static const _host = 'api.guildwars2.com';
  static const _pageSize = 200;

  final http.Client _client;

  HttpGw2Api({http.Client? client}) : _client = client ?? http.Client();

  /// Releases the underlying connection pool.
  void close() => _client.close();

  Map<String, String> _auth(String apiKey) =>
      {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'};

  Future<http.Response> _getResponse(
    String path, {
    Map<String, String>? query,
    String? apiKey,
  }) async {
    final uri = Uri.https(_host, path, query);
    late http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: apiKey == null ? null : _auth(apiKey),
      );
    } catch (e) {
      throw Gw2ApiException('Network error reaching $path: $e');
    }
    if (response.statusCode == 401) {
      throw const InvalidApiKeyException();
    }
    if (response.statusCode == 403) {
      throw MissingPermissionException(path);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Gw2ApiException(
        '$path returned HTTP ${response.statusCode}',
      );
    }
    return response;
  }

  Future<dynamic> _getJson(
    String path, {
    Map<String, String>? query,
    String? apiKey,
  }) async {
    final response =
        await _getResponse(path, query: query, apiKey: apiKey);
    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw Gw2ApiException('Could not parse $path response: $e');
    }
  }

  @override
  Future<List<String>> fetchTokenPermissions(String apiKey) async {
    // /v2/tokeninfo is the cheapest keyed call: 401 on a bad key, and its
    // `permissions` array tells us what this key may touch.
    final data = await _getJson('/v2/tokeninfo', apiKey: apiKey);
    if (data is Map<String, dynamic>) {
      final perms = data['permissions'];
      if (perms is List) {
        return [
          for (final p in perms)
            if (p is String) p
        ];
      }
    }
    return [];
  }

  @override
  Future<int> fetchWalletCoins(String apiKey) async {
    final data = await _getJson('/v2/account/wallet', apiKey: apiKey);
    if (data is! List) return 0;
    for (final row in data) {
      if (row is Map<String, dynamic> && row['id'] == 1) {
        final value = row['value'];
        if (value is int) return value;
        if (value is num) return value.toInt();
      }
    }
    return 0;
  }

  @override
  Future<DeliveryBox> fetchDelivery(String apiKey) async {
    final data = await _getJson('/v2/commerce/delivery', apiKey: apiKey);
    if (data is Map<String, dynamic>) {
      return DeliveryBox.fromJson(data);
    }
    return const DeliveryBox(coins: 0, items: []);
  }

  @override
  Future<List<TpOrder>> fetchCurrentOrders(
    String apiKey,
    String side,
  ) async {
    assert(side == 'buys' || side == 'sells', 'side must be buys or sells');
    final orders = <TpOrder>[];
    var page = 0;
    while (true) {
      final data = await _getJson(
        '/v2/commerce/transactions/current/$side',
        query: {'page': '$page', 'page_size': '$_pageSize'},
        apiKey: apiKey,
      );
      if (data is! List || data.isEmpty) break;
      for (final row in data) {
        if (row is Map<String, dynamic>) {
          final order = TpOrder.fromJson(row);
          if (order.itemId > 0 && order.quantity > 0) orders.add(order);
        }
      }
      if (data.length < _pageSize) break;
      page++;
      if (page > 50) break; // sanity bound; a page loop must terminate
    }
    return orders;
  }

  @override
  Future<List<InventoryEntry>> fetchInventory(String apiKey) async {
    final entries = <InventoryEntry>[];

    // Bank, crafting materials, shared inventory slots — independent
    // endpoints, fetched concurrently.
    final shared = await Future.wait([
      _safeGet('/v2/account/bank', apiKey),
      _safeGet('/v2/account/materials', apiKey),
      _safeGet('/v2/account/inventory', apiKey),
    ]);
    _addStacksTo(entries, shared[0], 'Bank');
    _addStacksTo(entries, shared[1], 'Materials');
    _addStacksTo(entries, shared[2], 'Shared Inventory');

    // Per-character bags and equipped gear. Guarded per character: a missing
    // `characters`/`inventories` permission (or one bad character) must not
    // wipe out the bank/materials/shared data we already have.
    try {
      // Plain /v2/characters returns the name list. (?ids=all would expand
      // to full character objects — not what we iterate here.)
      final characters = await _getJson(
        '/v2/characters',
        apiKey: apiKey,
      );
      if (characters is List) {
        final names = <String>[];
        for (final row in characters) {
          // Defensive: accept a bare name or a full character object.
          final name = row is String
              ? row
              : (row is Map<String, dynamic> ? row['name'] as String? : null);
          if (name != null && name.isNotEmpty) names.add(name);
        }
        // Characters are independent: fetch them concurrently instead of
        // one at a time. GW2 allows 600 req/min, so a dozen parallel
        // characters (each needing inventory + equipment) are safe.
        final results = await Future.wait(
          names.map((name) => _fetchCharacterEntries(apiKey, name)),
        );
        for (final r in results) {
          entries.addAll(r);
        }
      }
    } on InvalidApiKeyException {
      rethrow;
    } catch (_) {
      // No character access (e.g. missing permission): bank, materials and
      // shared slots above still stand.
    }
    return entries;
  }

  /// GET that returns null on any non-auth failure; auth failures rethrow
  /// so a bad key still surfaces as a hard error.
  Future<dynamic> _safeGet(String path, String apiKey) async {
    try {
      return await _getJson(path, apiKey: apiKey);
    } on InvalidApiKeyException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// One character's bags + equipped gear. Never throws (except on an
  /// invalid key): a single bad character must not wipe the rest of the
  /// inventory.
  Future<List<InventoryEntry>> _fetchCharacterEntries(
    String apiKey,
    String name,
  ) async {
    final entries = <InventoryEntry>[];
    // Do NOT pre-encode the name: _getJson builds the URI with Uri.https,
    // which percent-encodes the path itself. Pre-encoding turns a space
    // into %20 and then %2520, the API 404s, _safeGet swallows it, and a
    // character with a space in their name silently vanishes from
    // inventory.
    // Inventory and equipment are independent endpoints.
    final fetched = await Future.wait([
      _safeGet('/v2/characters/$name/inventory', apiKey),
      _safeGet('/v2/characters/$name/equipment', apiKey),
    ]);

    final bags = fetched[0];
    var bagIndex = 0;
    if (bags is Map<String, dynamic>) {
      final bagList = bags['bags'];
      if (bagList is List) {
        for (final bag in bagList) {
          bagIndex++;
          if (bag is Map<String, dynamic>) {
            final n = bagIndex;
            _addStacksTo(
              entries,
              bag['inventory'],
              name,
              detailFor: (_) => 'Bag $n',
            );
          }
        }
      }
    }
    // Equipped gear (weapons, armor, trinkets, …) — not in bags.
    final equipment = fetched[1];
    if (equipment is Map<String, dynamic>) {
      final gear = equipment['equipment'];
      if (gear is List) {
        for (final piece in gear) {
          if (piece is Map<String, dynamic>) {
            final id = piece['id'];
            final slot = piece['slot'];
            if (id is int && id > 0) {
              final binding = piece['binding'];
              entries.add(
                InventoryEntry(
                  itemId: id,
                  count: 1,
                  location: name,
                  detail: slot is String && slot.isNotEmpty
                      ? 'Equipped · $slot'
                      : 'Equipped',
                  binding:
                      binding is String && binding.isNotEmpty ? binding : null,
                ),
              );
            }
          }
        }
      }
    }
    return entries;
  }

  /// Appends item stacks from a raw bag/bank/materials list to [entries].
  static void _addStacksTo(
    List<InventoryEntry> entries,
    dynamic data,
    String location, {
    String? Function(int index)? detailFor,
  }) {
    if (data is! List) return;
    var index = 0;
    for (final row in data) {
      index++;
      if (row is Map<String, dynamic>) {
        final id = row['id'];
        final count = row['count'];
        if (id is int && id > 0 && count is int && count > 0) {
          final binding = row['binding'];
          entries.add(
            InventoryEntry(
              itemId: id,
              count: count,
              location: location,
              detail: detailFor?.call(index),
              binding: binding is String && binding.isNotEmpty ? binding : null,
            ),
          );
        }
      }
      // null rows are empty slots — skipped
    }
  }

  @override
  Future<HistoryPage> fetchHistory(
    String apiKey,
    String side, {
    int page = 0,
  }) async {
    assert(side == 'buys' || side == 'sells', 'side must be buys or sells');
    final response = await _getResponse(
      '/v2/commerce/transactions/history/$side',
      query: {'page': '$page', 'page_size': '${Gw2Api.historyPageSize}'},
      apiKey: apiKey,
    );
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (e) {
      throw Gw2ApiException('Could not parse history response: $e');
    }
    final rows = [
      if (data is List)
        for (final row in data)
          if (row is Map<String, dynamic>) row,
    ];
    return HistoryPage(rows, _pageTotal(response.headers));
  }

  /// The X-Page-Total response header: how many pages the API holds for
  /// this query. -1 when absent or unparseable.
  int _pageTotal(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'x-page-total') {
        return int.tryParse(entry.value.trim()) ?? -1;
      }
    }
    return -1;
  }

  @override
  Future<Map<int, ItemMeta>> fetchItemMeta(List<int> ids) async {
    final result = <int, ItemMeta>{};
    // The items endpoint accepts up to 200 ids per call; chunks are
    // independent, so fetch them concurrently.
    final chunks = <List<int>>[];
    for (var i = 0; i < ids.length; i += 200) {
      chunks.add(ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200));
    }
    final fetched = await Future.wait(chunks.map((chunk) async {
      final map = <int, ItemMeta>{};
      try {
        final data = await _getJson(
          '/v2/items',
          query: {'ids': chunk.join(',')},
        );
        if (data is List) {
          for (final row in data) {
            if (row is Map<String, dynamic>) {
              final meta = ItemMeta.fromJson(row);
              if (meta.id > 0) map[meta.id] = meta;
            }
          }
        }
      } catch (_) {
        // One bad chunk (e.g. a network blip) must not poison the whole
        // warm: without this, a single failed chunk discards every other
        // chunk's metadata and name search silently misses those items.
      }
      return map;
    }));
    for (final map in fetched) {
      result.addAll(map);
    }
    return result;
  }
}
