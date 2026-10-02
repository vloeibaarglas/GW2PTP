import 'package:gw2tp/api/gw2_client.dart';
import 'package:gw2tp/api/models.dart';

/// In-memory fake of the GW2 API for widget tests. Returns canned data and
/// never touches the network.
class FakeGw2Api implements Gw2Api {
  final bool validKey;
  int walletCoins;
  DeliveryBox delivery;
  List<TpOrder> buys;
  List<TpOrder> sells;

  /// Raw history rows for fetchHistory (side 'sells' shown on the Sold tab).
  List<Map<String, dynamic>> historySells;

  /// Raw history rows for fetchHistory (side 'buys' shown on the Bought tab).
  List<Map<String, dynamic>> historyBuys;

  /// Number of fetchHistory calls (both sides) — for asserting that
  /// covered range switches make no API call.
  int historyFetchCalls = 0;
  List<InventoryEntry> inventory;

  /// Permissions the fake key grants (default: everything the app needs).
  List<String> grantedPermissions;

  FakeGw2Api({
    this.validKey = true,
    this.walletCoins = 0,
    this.delivery = const DeliveryBox(coins: 0, items: []),
    this.buys = const [],
    this.sells = const [],
    this.historySells = const [],
    this.historyBuys = const [],
    this.inventory = const [],
    this.grantedPermissions = const [
      'wallet',
      'tradingpost',
      'inventories',
      'characters',
    ],
  });

  void _check() {
    if (!validKey) throw const InvalidApiKeyException();
  }

  @override
  Future<List<String>> fetchTokenPermissions(String apiKey) async {
    _check();
    return grantedPermissions;
  }

  @override
  Future<int> fetchWalletCoins(String apiKey) async {
    _check();
    return walletCoins;
  }

  @override
  Future<DeliveryBox> fetchDelivery(String apiKey) async {
    _check();
    return delivery;
  }

  @override
  Future<List<TpOrder>> fetchCurrentOrders(String apiKey, String side) async {
    _check();
    return side == 'buys' ? buys : sells;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchHistory(
    String apiKey,
    String side, {
    int page = 0,
  }) async {
    _check();
    historyFetchCalls++;
    // Mirror the real endpoint's paging: newest first, 200 rows per page.
    final rows = side == 'buys' ? historyBuys : historySells;
    final start = page * Gw2Api.historyPageSize;
    if (start >= rows.length) return [];
    final end = (start + Gw2Api.historyPageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  @override
  Future<List<InventoryEntry>> fetchInventory(String apiKey) async {
    _check();
    return inventory;
  }

  @override
  Future<Map<int, ItemMeta>> fetchItemMeta(List<int> ids) async => {};
}
