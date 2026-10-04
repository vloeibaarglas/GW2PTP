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

  /// Per-side fetchHistory counts, for asserting concurrent/queued syncs.
  final Map<String, int> historyFetchCallsBySide = {'sells': 0, 'buys': 0};

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

  /// Artificial delay per history fetch, so tests can let concurrent
  /// batches overlap. Defaults to none.
  Duration historyFetchDelay = Duration.zero;

  /// Highest number of simultaneously in-flight history fetches observed.
  int maxConcurrentHistoryFetches = 0;
  int _inFlightHistoryFetches = 0;

  @override
  Future<HistoryPage> fetchHistory(
    String apiKey,
    String side, {
    int page = 0,
  }) async {
    _check();
    historyFetchCalls++;
    historyFetchCallsBySide[side] = (historyFetchCallsBySide[side] ?? 0) + 1;
    _inFlightHistoryFetches++;
    if (_inFlightHistoryFetches > maxConcurrentHistoryFetches) {
      maxConcurrentHistoryFetches = _inFlightHistoryFetches;
    }
    try {
      if (historyFetchDelay > Duration.zero) {
        await Future.delayed(historyFetchDelay);
      }
      // Mirror the real endpoint's paging: newest first, 200 rows per page.
      final rows = side == 'buys' ? historyBuys : historySells;
      final pageTotal =
          (rows.length + Gw2Api.historyPageSize - 1) ~/ Gw2Api.historyPageSize;
      final start = page * Gw2Api.historyPageSize;
      if (start >= rows.length) return HistoryPage([], pageTotal);
      final end = (start + Gw2Api.historyPageSize).clamp(0, rows.length);
      return HistoryPage(rows.sublist(start, end), pageTotal);
    } finally {
      _inFlightHistoryFetches--;
    }
  }

  @override
  Future<List<InventoryEntry>> fetchInventory(String apiKey) async {
    _check();
    return inventory;
  }

  @override
  Future<Map<int, ItemMeta>> fetchItemMeta(List<int> ids) async => {};
}
