/// Central app state: API key, synced data, sync settings, and the
/// stale-data bookkeeping for passive mode.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/gw2_client.dart';
import '../api/models.dart';
import '../api/permissions.dart';
import '../store/data_cache.dart';
import '../store/item_meta_cache.dart';
import '../store/key_store.dart';
import '../store/sync_settings.dart';
import '../store/theme_settings.dart';
import '../sync/background_sync.dart';
import '../sync/fill_notifier.dart';
import '../util/clock_time.dart';
import '../util/coins.dart';

enum LoadStatus { idle, loading, loaded, error }

/// Time window for a history fetch. The app pages through history/buys or
/// history/sells (newest first) until the window is covered, capped at
/// [AppState.historyMaxPages] pages.
///
/// Hour presets are fixed; day granularity (1–30 days) comes from the rotary
/// dial via [HistoryRange.days]. Equality is by window, so
/// `HistoryRange.days(7) == HistoryRange.d7`.
class HistoryRange {
  final String label;
  final Duration window;
  const HistoryRange._(this.label, this.window);

  static const h1 = HistoryRange._('1H', Duration(hours: 1));
  static const h6 = HistoryRange._('6H', Duration(hours: 6));
  static const h24 = HistoryRange._('24H', Duration(hours: 24));
  static const d3 = HistoryRange._('3D', Duration(days: 3));
  static const d7 = HistoryRange._('7D', Duration(days: 7));

  /// The presets (what the old enum exposed as `values`).
  static const values = [h1, h6, h24, d3, d7];

  /// Day-granularity range from the dial, clamped to 1–30 days.
  factory HistoryRange.days(int days) {
    final d = days.clamp(1, 30);
    if (d == 3) return d3;
    if (d == 7) return d7;
    return HistoryRange._('${d}D', Duration(days: d));
  }

  /// Day count when this is a day-granularity range, null for hour presets.
  int? get dayCount {
    final m = RegExp(r'^(\d+)D$').firstMatch(label);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Stable persistence key. The preset names match the old enum names so
  /// existing saved preferences keep working; dial values store as 'dN'.
  String get storageKey {
    if (identical(this, h1)) return 'h1';
    if (identical(this, h6)) return 'h6';
    if (identical(this, h24)) return 'h24';
    if (identical(this, d3)) return 'd3';
    if (identical(this, d7)) return 'd7';
    final d = dayCount;
    return d == null ? 'h24' : 'd$d';
  }

  /// Parses a stored [storageKey]; unknown values fall back to 24h.
  static HistoryRange parse(String raw) {
    switch (raw) {
      case 'h1':
        return h1;
      case 'h6':
        return h6;
      case 'h24':
        return h24;
      case 'd3':
        return d3;
      case 'd7':
        return d7;
    }
    final m = RegExp(r'^d(\d+)$').firstMatch(raw);
    if (m != null) return HistoryRange.days(int.parse(m.group(1)!));
    return h24;
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryRange && other.window == window;

  @override
  int get hashCode => window.hashCode;

  @override
  String toString() => 'HistoryRange($label)';
}

/// How history rows are grouped. Mirrors the web app's collapse toggle:
/// every transaction, one row per item (weighted-average price), or one row
/// per (item, price) point.
enum HistoryGrouping { txn, item, price }

/// How open listings are grouped: every order, one row per item
/// (weighted-average price), or one row per (item, price) point.
enum OrderGrouping {
  order('By Order'),
  item('By Item'),
  price('By Price');

  const OrderGrouping(this.label);
  final String label;
}

/// Keeps the rows inside the trailing [window]; rows without a timestamp
/// are always kept (they cannot be range-filtered).
List<TpTransaction> _inWindow(List<TpTransaction> rows, Duration window) {
  final cutoff = DateTime.now().subtract(window);
  return [
    for (final t in rows)
      if (t.filledAt == null || !t.filledAt!.isBefore(cutoff)) t,
  ];
}

/// Result of one paged history fetch.
class _HistoryFetch {
  final List<TpTransaction> rows;
  final bool capped;
  final DateTime coveredSince;
  const _HistoryFetch(this.rows, this.capped, this.coveredSince);
}

class AppState extends ChangeNotifier {
  final KeyStore _keys;
  final Gw2Api _api;
  final SyncSettings settings;
  final ThemeSettings themeSettings;
  final ItemMetaCache meta;
  final FillNotifier notifier;
  final SyncService syncService;
  final DataCache _cache;

  AppState({
    required KeyStore keys,
    required Gw2Api api,
    required SharedPreferences prefs,
    required this.notifier,
    required this.syncService,
    DataCache? dataCache,
  })  : _keys = keys,
        _api = api,
        settings = SyncSettings(prefs),
        themeSettings = ThemeSettings(prefs),
        meta = ItemMetaCache(prefs),
        _cache = dataCache ?? DataCache(prefs);

  bool _keyLoaded = false;
  String? _apiKey;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  LoadStatus status = LoadStatus.idle;
  String? errorMessage;
  bool invalidKey = false;

  /// Permissions from [requiredApiPermissions] the key is missing.
  /// Checked on entry and on key save; drives the warning banner.
  List<String> missingPermissions = const [];
  bool get hasMissingPermissions => missingPermissions.isNotEmpty;

  /// Non-fatal per-section failures from the last sync (e.g. one endpoint
  /// down). Null when everything loaded.
  String? sectionNotice;

  int walletCoins = 0;
  DeliveryBox delivery = const DeliveryBox(coins: 0, items: []);
  List<TpOrder> buys = [];
  List<TpOrder> sells = [];

  /// All fetched sell transactions (newest first), covering back to
  /// [soldHistoryCoveredSince]. The [soldHistory] view filters these to
  /// [soldRange], so narrowing the range never needs a re-fetch.
  List<TpTransaction> _soldHistoryCache = [];

  /// Ids of the transactions in [_soldHistoryCache]. Lets incremental
  /// fetches recognize rows we've already seen (the history endpoints
  /// offer no cursor — only newest-first pages), so refreshes stop at the
  /// first fully-known page instead of re-downloading everything.
  final Set<int> _seenSoldIds = {};

  /// Recently filled sell transactions, newest first, filtered to [soldRange].
  List<TpTransaction> get soldHistory =>
      _inWindow(_soldHistoryCache, soldRange.window);

  /// All fetched buy transactions (newest first), covering back to
  /// [boughtHistoryCoveredSince].
  List<TpTransaction> _boughtHistoryCache = [];

  /// Ids of the transactions in [_boughtHistoryCache] (see [_seenSoldIds]).
  final Set<int> _seenBoughtIds = {};

  /// Recently filled buy transactions, newest first, filtered to [boughtRange].
  List<TpTransaction> get boughtHistory =>
      _inWindow(_boughtHistoryCache, boughtRange.window);

  /// Maximum history pages fetched per sync (200 rows each, so 2,000
  /// transactions). The lookback either history tab can ever show.
  static const historyMaxPages = 10;

  /// The time window the Sold tab shows. Persisted; defaults to 24h.
  HistoryRange soldRange = HistoryRange.h24;

  /// The time window the Bought tab shows. Persisted; defaults to 24h.
  HistoryRange boughtRange = HistoryRange.h24;

  /// How the Sold tab groups history rows. Persisted; defaults to By Txn.
  HistoryGrouping soldGrouping = HistoryGrouping.txn;

  /// How the Bought tab groups history rows. Persisted; defaults to By Txn.
  HistoryGrouping boughtGrouping = HistoryGrouping.txn;

  /// How the Listings > Selling tab groups open orders.
  /// Persisted; defaults to By Order.
  OrderGrouping sellingGrouping = OrderGrouping.order;

  /// How the Listings > Buying tab groups open orders.
  /// Persisted; defaults to By Order.
  OrderGrouping buyingGrouping = OrderGrouping.order;

  /// True when the last sale-history fetch hit [historyMaxPages] with a
  /// full final page — older transactions may exist beyond the 2,000 shown.
  bool soldHistoryCapped = false;

  /// True when the last buy-history fetch hit [historyMaxPages] with a
  /// full final page.
  bool boughtHistoryCapped = false;

  /// Earliest time the cached histories completely cover. Fetches are
  /// newest-first and contiguous, so everything from here to now is present.
  DateTime soldHistoryCoveredSince = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime boughtHistoryCoveredSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// When the histories were last fetched. Informational — range switches
  /// never consult it; only explicit refresh/sync updates the cache.
  DateTime soldHistoryFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime boughtHistoryFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<InventoryEntry> inventory = [];
  bool serviceRunning = false;

  bool get keyLoaded => _keyLoaded;
  bool get hasKey => _apiKey != null;
  String get maskedKey => maskApiKey(_apiKey);

  /// Age of the last successful sync. Zero when never synced.
  Duration get dataAge {
    final ms = settings.lastSyncAtMs;
    if (ms <= 0) return Duration.zero;
    return DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  bool get neverSynced => settings.lastSyncAtMs <= 0;

  /// Passive mode shows a stale warning once data is older than an hour.
  bool get isStale => !neverSynced && dataAge > const Duration(hours: 1);

  /// When the last successful sync happened, as local clock time:
  /// "at 3:42 PM", or "at 9/29 3:42 PM" when not today.
  String get lastSyncLabel {
    if (neverSynced) return 'just now';
    final dt = DateTime.fromMillisecondsSinceEpoch(settings.lastSyncAtMs);
    return 'at ${formatClockTime(dt)}';
  }

  /// Boot: load the key, restore the last sync's data from disk so the
  /// first frame is never empty, then sync in passive mode or ensure the
  /// service is up in active mode.
  Future<void> init() async {
    _apiKey = await _keys.readApiKey();
    _loadHistoryViewPrefs();
    // After a swipe-away the process is gone; without this the app shows
    // empty lists until the API refresh below completes. The refresh still
    // runs — the cache just covers the gap.
    await _restoreCache();
    _keyLoaded = true;
    notifyListeners();
    if (_apiKey == null) return;
    await _checkPermissions(_apiKey!);
    if (settings.mode == SyncMode.active) {
      await _ensureService();
      // Still do one foreground refresh so the UI is never empty.
      await refreshAll();
    } else {
      await refreshAll();
    }
  }

  /// Called when the app returns to the foreground: passive mode syncs on
  /// every open.
  Future<void> onResumed() async {
    if (!hasKey || status == LoadStatus.loading) return;
    await settings.reload();
    if (settings.mode == SyncMode.active) {
      // The system can kill the foreground service while the app is
      // backgrounded (Samsung is aggressive about this); the old code only
      // ensured the service at boot, so a killed service stayed dead —
      // ticks stopped and fill notifications with them. Re-check on every
      // foregrounding and restart when it's gone.
      try {
        if (await syncService.isRunning) {
          serviceRunning = true;
        } else {
          await _ensureService();
        }
      } catch (_) {
        serviceRunning = false;
      }
      notifyListeners();
    }
    // Don't hammer the API when the app was backgrounded for seconds;
    // pull-to-refresh stays manual.
    if (!neverSynced && dataAge < const Duration(minutes: 2)) return;
    await refreshAll();
  }

  /// Re-reads background-tick status written by the background isolate and
  /// the live service state. The Settings screen calls this to show whether
  /// the notification pipeline is actually alive.
  Future<void> refreshSyncStatus() async {
    await settings.reload();
    try {
      serviceRunning = await syncService.isRunning;
    } catch (_) {
      serviceRunning = false;
    }
    notifyListeners();
  }

  /// "Last check 3:42 PM · notified 2 fills", or a never-ran note.
  String get lastTickLabel {
    final ms = settings.lastTickAtMs;
    if (ms <= 0) return 'Background check has never run.';
    final at = formatClockTime(DateTime.fromMillisecondsSinceEpoch(ms));
    final result = settings.lastTickResult;
    return result.isEmpty ? 'Last check $at.' : 'Last check $at · $result.';
  }

  /// Checks the key's granted permissions against [requiredApiPermissions].
  /// Runs on entry and on key save. Network failures leave the previous
  /// value alone — no nagging when we simply couldn't reach the API.
  Future<void> _checkPermissions(String key) async {
    try {
      final granted = await _api.fetchTokenPermissions(key);
      missingPermissions = missingApiPermissions(granted);
    } catch (_) {
      // Keep the previous value; the sync itself will surface real errors.
    }
    notifyListeners();
  }

  /// Manual re-check from Settings.
  Future<void> recheckPermissions() async {
    final key = _apiKey;
    if (key == null) return;
    await _checkPermissions(key);
  }

  /// Restores the last successful sync from disk. Runs at boot before the
  /// first frame so a cold start shows data instantly. A missing or
  /// corrupt cache leaves the (empty) in-memory state alone — never throws.
  Future<void> _restoreCache() async {
    final snap = await _cache.load();
    if (snap == null) return;
    walletCoins = snap.walletCoins;
    delivery = snap.delivery;
    buys = snap.buys;
    sells = snap.sells;
    _soldHistoryCache = snap.soldHistory;
    _boughtHistoryCache = snap.boughtHistory;
    _seenSoldIds
      ..clear()
      ..addAll(snap.soldHistory.map((t) => t.id));
    _seenBoughtIds
      ..clear()
      ..addAll(snap.boughtHistory.map((t) => t.id));
    soldHistoryCoveredSince =
        DateTime.fromMillisecondsSinceEpoch(snap.soldCoveredSinceMs);
    boughtHistoryCoveredSince =
        DateTime.fromMillisecondsSinceEpoch(snap.boughtCoveredSinceMs);
    soldHistoryCapped = snap.soldCapped;
    boughtHistoryCapped = snap.boughtCapped;
    soldHistoryFetchedAt =
        DateTime.fromMillisecondsSinceEpoch(snap.soldFetchedAtMs);
    boughtHistoryFetchedAt =
        DateTime.fromMillisecondsSinceEpoch(snap.boughtFetchedAtMs);
    inventory = snap.inventory;
  }

  /// Persists the current state after a successful sync. A failed write
  /// never fails the sync — the previous cache stays in place.
  Future<void> _saveCache() async {
    try {
      await _cache.save(
        DataSnapshot(
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
          walletCoins: walletCoins,
          delivery: delivery,
          buys: buys,
          sells: sells,
          soldHistory: _soldHistoryCache,
          boughtHistory: _boughtHistoryCache,
          soldCoveredSinceMs: soldHistoryCoveredSince.millisecondsSinceEpoch,
          boughtCoveredSinceMs:
              boughtHistoryCoveredSince.millisecondsSinceEpoch,
          soldCapped: soldHistoryCapped,
          boughtCapped: boughtHistoryCapped,
          soldFetchedAtMs: soldHistoryFetchedAt.millisecondsSinceEpoch,
          boughtFetchedAtMs: boughtHistoryFetchedAt.millisecondsSinceEpoch,
          inventory: inventory,
        ),
      );
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    final key = _apiKey;
    if (key == null) return;
    if (status == LoadStatus.loading) return;
    status = LoadStatus.loading;
    errorMessage = null;
    sectionNotice = null;
    invalidKey = false;
    notifyListeners();

    // Each section loads independently: a missing permission (or one flaky
    // endpoint) blanks only its own section instead of failing the sync.
    final failures = <String>[];
    Future<void> guard(String name, Future<void> Function() load) async {
      try {
        await load();
      } on InvalidApiKeyException {
        rethrow;
      } catch (_) {
        failures.add(name);
      }
    }

    try {
      await Future.wait([
        guard('wallet', () async {
          walletCoins = await _api.fetchWalletCoins(key);
        }),
        guard('delivery box', () async {
          delivery = await _api.fetchDelivery(key);
        }),
        guard('buy orders', () async {
          buys = await _api.fetchCurrentOrders(key, 'buys');
        }),
        guard('sell orders', () async {
          sells = await _api.fetchCurrentOrders(key, 'sells');
        }),
        guard('sale history', () => _syncSoldHistory(key)),
        guard('purchase history', () => _syncBoughtHistory(key)),
        guard('inventory', () async {
          inventory = await _api.fetchInventory(key);
        }),
      ]);

      if (failures.length >= 7) {
        // Nothing at all loaded — treat like a sync failure.
        status = LoadStatus.error;
        errorMessage =
            'Sync failed: none of the sections loaded (${failures.join(', ')}).';
      } else {
        final ids = <int>{
          for (final e in inventory) e.itemId,
          for (final e in delivery.items) e.itemId,
          for (final o in buys) o.itemId,
          for (final o in sells) o.itemId,
          for (final t in soldHistory) t.itemId,
          for (final t in boughtHistory) t.itemId,
        };
        await meta.warm(ids, _api.fetchItemMeta);

        await settings.setLastSyncAtMs(DateTime.now().millisecondsSinceEpoch);
        await _saveCache();
        status = LoadStatus.loaded;
        if (failures.isNotEmpty) {
          sectionNotice = "Couldn't load: ${failures.join(', ')}.";
        }
      }
    } on InvalidApiKeyException {
      invalidKey = true;
      status = LoadStatus.error;
      errorMessage = 'The API key was rejected. Check it in Settings.';
    } catch (e) {
      status = LoadStatus.error;
      errorMessage = 'Sync failed: ${_shortError(e)}';
    }
    notifyListeners();
  }

  /// One paged history fetch, incremental: rows already in [existing]
  /// (tracked by [seenIds]) are skipped, and the walk stops early instead
  /// of re-downloading them.
  ///
  /// The history endpoints expose no cursor or `since` parameter — only
  /// newest-first `page`/`page_size` — so the transaction `id` is the
  /// identification mechanism, and we build the incrementality ourselves:
  /// - refresh (same window, [stopAtKnown] true): new transactions can only
  ///   appear at the top, so the walk stops at the first page holding
  ///   nothing new. A refresh is usually 1–2 pages, not up to 10.
  /// - widen ([stopAtKnown] false): older rows live on deeper pages, so the
  ///   walk continues through already-known pages (skipping their rows)
  ///   until the window's cutoff — those pages must still be downloaded,
  ///   the API offers no way to jump past them.
  ///
  /// [coveredSince] is the earliest time fully covered — the fetch ran
  /// newest-first and contiguous from now back to here.
  Future<_HistoryFetch> _loadHistory(
    String key,
    String side,
    Duration window, {
    required List<TpTransaction> existing,
    required Set<int> seenIds,
    required bool stopAtKnown,
    required bool prevCapped,
    required DateTime prevCoveredSince,
  }) async {
    final cutoff = DateTime.now().subtract(window);
    final fresh = <TpTransaction>[];
    var capped = false;
    var reachedCutoff = false;
    var stoppedAtKnown = false;
    for (var page = 0; page < historyMaxPages; page++) {
      final data = await _api.fetchHistory(key, side, page: page);
      if (data.isEmpty) break;
      var pageAllKnown = true;
      var pageHitCutoff = false;
      for (final row in data) {
        final t = TpTransaction.fromJson(row);
        if (t.id <= 0 || t.itemId <= 0) continue;
        if (seenIds.contains(t.id)) continue; // already cached: skip
        pageAllKnown = false;
        if (t.filledAt != null && t.filledAt!.isBefore(cutoff)) {
          // Older than the window — and older than anything a later
          // widen could want from this walk, so don't mark it seen.
          pageHitCutoff = true;
          break;
        }
        seenIds.add(t.id);
        fresh.add(t);
      }
      if (pageHitCutoff) {
        reachedCutoff = true;
        break;
      }
      if (stopAtKnown && pageAllKnown) {
        stoppedAtKnown = true;
        break;
      }
      if (data.length < Gw2Api.historyPageSize) break;
      if (page == historyMaxPages - 1) capped = true;
    }

    final rows = _mergeHistory(existing, fresh);
    if (reachedCutoff) {
      return _HistoryFetch(rows, false, cutoff);
    }
    if (capped) {
      // Hit the 10-page cap: coverage ends at the oldest row we hold.
      DateTime? oldest;
      for (final t in rows) {
        final ft = t.filledAt;
        if (ft != null && (oldest == null || ft.isBefore(oldest))) {
          oldest = ft;
        }
      }
      return _HistoryFetch(rows, true, oldest ?? cutoff);
    }
    if (stoppedAtKnown) {
      // Nothing new beyond what we hold: prior coverage still stands.
      return _HistoryFetch(rows, prevCapped, prevCoveredSince);
    }
    // Walked the API to exhaustion without hitting the cutoff: we hold
    // every transaction that exists.
    return _HistoryFetch(rows, false, DateTime.fromMillisecondsSinceEpoch(0));
  }

  /// Merges freshly fetched rows into the cached history: de-duplicated by
  /// transaction id, newest-first.
  List<TpTransaction> _mergeHistory(
      List<TpTransaction> existing, List<TpTransaction> fresh) {
    if (fresh.isEmpty) return existing;
    final seen = <int>{};
    final merged = <TpTransaction>[];
    for (final t in fresh) {
      if (seen.add(t.id)) merged.add(t);
    }
    for (final t in existing) {
      if (seen.add(t.id)) merged.add(t);
    }
    merged.sort((a, b) {
      final at = a.filledAt;
      final bt = b.filledAt;
      if (at != null && bt != null) {
        final c = bt.compareTo(at);
        if (c != 0) return c;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return b.id.compareTo(a.id);
    });
    return merged;
  }

  /// Loads and stores the sale history for [soldRange], incrementally:
  /// only transactions not already cached are kept from the fetch.
  Future<void> _syncSoldHistory(String key, {bool stopAtKnown = true}) async {
    final r = await _loadHistory(
      key,
      'sells',
      soldRange.window,
      existing: _soldHistoryCache,
      seenIds: _seenSoldIds,
      stopAtKnown: stopAtKnown,
      prevCapped: soldHistoryCapped,
      prevCoveredSince: soldHistoryCoveredSince,
    );
    _soldHistoryCache = r.rows;
    soldHistoryCapped = r.capped;
    soldHistoryCoveredSince = r.coveredSince;
    soldHistoryFetchedAt = DateTime.now();
  }

  /// Loads and stores the buy history for [boughtRange] (same incremental
  /// semantics as [_syncSoldHistory]).
  Future<void> _syncBoughtHistory(String key, {bool stopAtKnown = true}) async {
    final r = await _loadHistory(
      key,
      'buys',
      boughtRange.window,
      existing: _boughtHistoryCache,
      seenIds: _seenBoughtIds,
      stopAtKnown: stopAtKnown,
      prevCapped: boughtHistoryCapped,
      prevCoveredSince: boughtHistoryCoveredSince,
    );
    _boughtHistoryCache = r.rows;
    boughtHistoryCapped = r.capped;
    boughtHistoryCoveredSince = r.coveredSince;
    boughtHistoryFetchedAt = DateTime.now();
  }

  /// True when the cached history already covers [window], so switching to
  /// it is a pure local filter — no API call. Staleness never triggers a
  /// fetch here; only explicit refresh/sync updates the cache.
  bool _coversWindow(DateTime coveredSince, Duration window) {
    return !DateTime.now().subtract(window).isBefore(coveredSince);
  }

  /// Loads the persisted history view preferences (grouping + range per
  /// tab). Defaults: By Txn, 24h.
  void _loadHistoryViewPrefs() {
    HistoryGrouping parseGrouping(String raw) =>
        HistoryGrouping.values.firstWhere(
          (g) => g.name == raw,
          orElse: () => HistoryGrouping.txn,
        );
    HistoryRange parseRange(String raw) => HistoryRange.parse(raw);
    soldGrouping =
        parseGrouping(settings.historyViewPref('sold_grouping', 'txn'));
    soldRange = parseRange(settings.historyViewPref('sold_range', 'h24'));
    boughtGrouping =
        parseGrouping(settings.historyViewPref('bought_grouping', 'txn'));
    boughtRange = parseRange(settings.historyViewPref('bought_range', 'h24'));
    OrderGrouping parseOrderGrouping(String raw) => OrderGrouping.values
        .firstWhere((g) => g.name == raw, orElse: () => OrderGrouping.order);
    sellingGrouping = parseOrderGrouping(
        settings.historyViewPref('listing_selling_grouping', 'order'));
    buyingGrouping = parseOrderGrouping(
        settings.historyViewPref('listing_buying_grouping', 'order'));
  }

  /// Switches the Sold tab grouping, persisting the choice.
  void setSoldGrouping(HistoryGrouping grouping) {
    if (grouping == soldGrouping) return;
    soldGrouping = grouping;
    settings.setHistoryViewPref('sold_grouping', grouping.name);
    notifyListeners();
  }

  /// Switches the Bought tab grouping, persisting the choice.
  void setBoughtGrouping(HistoryGrouping grouping) {
    if (grouping == boughtGrouping) return;
    boughtGrouping = grouping;
    settings.setHistoryViewPref('bought_grouping', grouping.name);
    notifyListeners();
  }

  /// Switches the Listings > Selling grouping, persisting the choice.
  void setSellingGrouping(OrderGrouping grouping) {
    if (grouping == sellingGrouping) return;
    sellingGrouping = grouping;
    settings.setHistoryViewPref('listing_selling_grouping', grouping.name);
    notifyListeners();
  }

  /// Switches the Listings > Buying grouping, persisting the choice.
  void setBuyingGrouping(OrderGrouping grouping) {
    if (grouping == buyingGrouping) return;
    buyingGrouping = grouping;
    settings.setHistoryViewPref('listing_buying_grouping', grouping.name);
    notifyListeners();
  }

  /// Switches the Sold tab time window. Narrowing (or widening within what
  /// the cache already covers) is always a pure local filter — never an API
  /// call. Only widening beyond the cached coverage fetches, and then only
  /// incrementally.
  Future<void> setSoldRange(HistoryRange range) async {
    if (range == soldRange) return;
    settings.setHistoryViewPref('sold_range', range.storageKey);
    final widening = range.window > soldRange.window;
    soldRange = range;
    if (_soldHistoryCache.isNotEmpty &&
        (!widening || _coversWindow(soldHistoryCoveredSince, range.window))) {
      // The filtered view is complete for this window — nothing truncated.
      soldHistoryCapped = false;
      notifyListeners();
      return;
    }
    notifyListeners();
    await refreshSoldHistory(stopAtKnown: !widening);
  }

  /// Switches the Bought tab time window (same instant-switch semantics as
  /// [setSoldRange]).
  Future<void> setBoughtRange(HistoryRange range) async {
    if (range == boughtRange) return;
    settings.setHistoryViewPref('bought_range', range.storageKey);
    final widening = range.window > boughtRange.window;
    boughtRange = range;
    if (_boughtHistoryCache.isNotEmpty &&
        (!widening || _coversWindow(boughtHistoryCoveredSince, range.window))) {
      boughtHistoryCapped = false;
      notifyListeners();
      return;
    }
    notifyListeners();
    await refreshBoughtHistory(stopAtKnown: !widening);
  }

  /// Re-fetches only the sale history (e.g. after the range changes),
  /// warming item metadata for any newly seen items. Incremental: pages
  /// holding only already-cached transactions end the walk early.
  Future<void> refreshSoldHistory({bool stopAtKnown = true}) async {
    final key = _apiKey;
    if (key == null || status == LoadStatus.loading) return;
    status = LoadStatus.loading;
    notifyListeners();
    try {
      await _syncSoldHistory(key, stopAtKnown: stopAtKnown);
      await meta.warm(
        {for (final t in soldHistory) t.itemId},
        _api.fetchItemMeta,
      );
      status = LoadStatus.loaded;
    } catch (_) {
      // Keep the previously loaded history on a failed range switch.
      status = LoadStatus.loaded;
    }
    notifyListeners();
  }

  /// Re-fetches only the buy history, warming item metadata for any newly
  /// seen items (same incremental semantics as [refreshSoldHistory]).
  Future<void> refreshBoughtHistory({bool stopAtKnown = true}) async {
    final key = _apiKey;
    if (key == null || status == LoadStatus.loading) return;
    status = LoadStatus.loading;
    notifyListeners();
    try {
      await _syncBoughtHistory(key, stopAtKnown: stopAtKnown);
      await meta.warm(
        {for (final t in boughtHistory) t.itemId},
        _api.fetchItemMeta,
      );
      status = LoadStatus.loaded;
    } catch (_) {
      // Keep the previously loaded history on a failed range switch.
      status = LoadStatus.loaded;
    }
    notifyListeners();
  }

  /// Validates [key] against the API before storing it, and records which
  /// of the required permissions it is missing.
  Future<String?> saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'Enter an API key.';
    List<String> granted;
    try {
      granted = await _api.fetchTokenPermissions(trimmed);
    } on InvalidApiKeyException {
      return 'That key was rejected by the GW2 API.';
    } catch (e) {
      return 'Could not reach the GW2 API: ${_shortError(e)}';
    }
    await _keys.writeApiKey(trimmed);
    _apiKey = trimmed;
    missingPermissions = missingApiPermissions(granted);
    notifyListeners();
    if (settings.mode == SyncMode.active) {
      await _ensureService();
    }
    await refreshAll();
    return null;
  }

  Future<void> clearKey() async {
    await syncService.stop();
    serviceRunning = false;
    await _keys.deleteApiKey();
    await _cache.clear();
    _apiKey = null;
    walletCoins = 0;
    delivery = const DeliveryBox(coins: 0, items: []);
    buys = [];
    sells = [];
    _soldHistoryCache = [];
    _boughtHistoryCache = [];
    _seenSoldIds.clear();
    _seenBoughtIds.clear();
    soldHistoryCapped = false;
    boughtHistoryCapped = false;
    soldHistoryCoveredSince = DateTime.fromMillisecondsSinceEpoch(0);
    boughtHistoryCoveredSince = DateTime.fromMillisecondsSinceEpoch(0);
    soldHistoryFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
    boughtHistoryFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
    inventory = [];
    status = LoadStatus.idle;
    errorMessage = null;
    sectionNotice = null;
    invalidKey = false;
    missingPermissions = const [];
    notifyListeners();
  }

  Future<void> setSyncMode(SyncMode mode) async {
    await settings.setMode(mode);
    if (mode == SyncMode.active) {
      await notifier.requestPermission();
      await _ensureService();
    } else {
      await syncService.stop();
      serviceRunning = false;
    }
    notifyListeners();
  }

  ThemeMode get themeMode => themeSettings.themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    await themeSettings.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    if (minutes == settings.intervalMinutes) return;
    await settings.setIntervalMinutes(minutes);
    if (settings.mode == SyncMode.active) {
      await _ensureService();
    }
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await settings.setNotificationsEnabled(enabled);
    if (enabled) await notifier.requestPermission();
    notifyListeners();
  }

  Future<void> _ensureService() async {
    try {
      await syncService.start(
        intervalMinutes: settings.intervalMinutes,
      );
      serviceRunning = true;
    } catch (_) {
      serviceRunning = false;
      errorMessage = 'Could not start background sync. Battery optimization or '
          'notification permission may be blocking it.';
    }
  }

  static String _shortError(Object e) {
    final text = e.toString().replaceFirst('Gw2ApiException: ', '');
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }
}
