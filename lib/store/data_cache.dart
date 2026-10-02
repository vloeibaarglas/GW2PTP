/// On-disk snapshot of the last successful sync.
///
/// Cold start (e.g. after swiping the app away) restores this before the
/// first frame, so the UI shows the data from the last sync instantly
/// instead of empty lists while the API refresh runs. A corrupt or
/// version-mismatched snapshot degrades to "no cache", never a crash.
///
/// Stored as one JSON string in SharedPreferences alongside the other
/// persisted app state (history view prefs, item metadata). Writes happen
/// once per successful sync, so the whole-value rewrite cost is negligible.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Everything [refreshAll] fetched, serialized after a successful sync.
class DataSnapshot {
  final int savedAtMs;
  final int walletCoins;
  final DeliveryBox delivery;
  final List<TpOrder> buys;
  final List<TpOrder> sells;
  final List<TpTransaction> soldHistory;
  final List<TpTransaction> boughtHistory;
  final int soldCoveredSinceMs;
  final int boughtCoveredSinceMs;
  final bool soldCapped;
  final bool boughtCapped;
  final int soldFetchedAtMs;
  final int boughtFetchedAtMs;
  final List<InventoryEntry> inventory;

  const DataSnapshot({
    required this.savedAtMs,
    required this.walletCoins,
    required this.delivery,
    required this.buys,
    required this.sells,
    required this.soldHistory,
    required this.boughtHistory,
    required this.soldCoveredSinceMs,
    required this.boughtCoveredSinceMs,
    required this.soldCapped,
    required this.boughtCapped,
    required this.soldFetchedAtMs,
    required this.boughtFetchedAtMs,
    required this.inventory,
  });

  Map<String, dynamic> toJson() => {
        'v': 1,
        'savedAtMs': savedAtMs,
        'walletCoins': walletCoins,
        'delivery': delivery.toJson(),
        'buys': [for (final o in buys) o.toJson()],
        'sells': [for (final o in sells) o.toJson()],
        'soldHistory': [for (final t in soldHistory) t.toJson()],
        'boughtHistory': [for (final t in boughtHistory) t.toJson()],
        'soldCoveredSinceMs': soldCoveredSinceMs,
        'boughtCoveredSinceMs': boughtCoveredSinceMs,
        'soldCapped': soldCapped,
        'boughtCapped': boughtCapped,
        'soldFetchedAtMs': soldFetchedAtMs,
        'boughtFetchedAtMs': boughtFetchedAtMs,
        'inventory': [for (final e in inventory) e.toJson()],
      };

  /// Returns null when the payload is not a version-1 snapshot.
  /// Individual malformed rows are skipped; the snapshot is never
  /// rejected wholesale because of one bad row.
  static DataSnapshot? fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) return null;
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    List<Map<String, dynamic>> asRows(dynamic v) => v is List
        ? [for (final r in v) if (r is Map<String, dynamic>) r]
        : <Map<String, dynamic>>[];

    DeliveryBox delivery;
    try {
      final raw = json['delivery'];
      delivery = raw is Map<String, dynamic>
          ? DeliveryBox.fromJson(raw)
          : const DeliveryBox(coins: 0, items: []);
    } catch (_) {
      delivery = const DeliveryBox(coins: 0, items: []);
    }

    List<TpOrder> orders(dynamic v) {
      final out = <TpOrder>[];
      for (final row in asRows(v)) {
        try {
          final o = TpOrder.fromJson(row);
          if (o.id > 0 && o.itemId > 0) out.add(o);
        } catch (_) {}
      }
      return out;
    }

    List<TpTransaction> transactions(dynamic v) {
      final out = <TpTransaction>[];
      for (final row in asRows(v)) {
        try {
          final t = TpTransaction.fromJson(row);
          if (t.id > 0 && t.itemId > 0) out.add(t);
        } catch (_) {}
      }
      return out;
    }

    List<InventoryEntry> entries(dynamic v) {
      final out = <InventoryEntry>[];
      for (final row in asRows(v)) {
        try {
          final e = InventoryEntry.fromJson(row);
          if (e.itemId > 0 && e.count > 0) out.add(e);
        } catch (_) {}
      }
      return out;
    }

    return DataSnapshot(
      savedAtMs: asInt(json['savedAtMs']),
      walletCoins: asInt(json['walletCoins']),
      delivery: delivery,
      buys: orders(json['buys']),
      sells: orders(json['sells']),
      soldHistory: transactions(json['soldHistory']),
      boughtHistory: transactions(json['boughtHistory']),
      soldCoveredSinceMs: asInt(json['soldCoveredSinceMs']),
      boughtCoveredSinceMs: asInt(json['boughtCoveredSinceMs']),
      soldCapped: json['soldCapped'] == true,
      boughtCapped: json['boughtCapped'] == true,
      soldFetchedAtMs: asInt(json['soldFetchedAtMs']),
      boughtFetchedAtMs: asInt(json['boughtFetchedAtMs']),
      inventory: entries(json['inventory']),
    );
  }
}

/// Reads/writes the [DataSnapshot] in SharedPreferences.
class DataCache {
  final SharedPreferences _prefs;

  DataCache(this._prefs);

  @visibleForTesting
  static const cacheKey = 'tp_data_cache_json';

  Future<void> save(DataSnapshot snapshot) async {
    await _prefs.setString(cacheKey, jsonEncode(snapshot.toJson()));
  }

  /// The last saved snapshot, or null when there is none / it is
  /// unreadable. Never throws.
  Future<DataSnapshot?> load() async {
    try {
      final raw = _prefs.getString(cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DataSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Drops the snapshot (key sign-out). Never throws.
  Future<void> clear() async {
    try {
      await _prefs.remove(cacheKey);
    } catch (_) {}
  }
}
