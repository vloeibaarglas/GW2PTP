/// Permanent on-disk cache of item metadata (name + icon URL).
///
/// Item metadata is static: an id's name and icon never change, so entries
/// never expire. New ids are fetched on demand in 200-id batches and merged
/// into the cache.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

class ItemMetaCache {
  // v2 adds rarity + type to each entry; v1 entries are refetched on
  // demand after the bump.
  static const _prefsKey = 'item_meta_cache_v2';

  final SharedPreferences _prefs;
  final Map<int, ItemMeta> _mem = {};
  bool _loaded = false;
  Timer? _persistTimer;

  ItemMetaCache(this._prefs);

  /// Decodes the persisted JSON on first use, not in the constructor, so
  /// AppState creation never pays a multi-MB jsonDecode on the UI thread.
  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((key, value) {
          final id = int.tryParse(key);
          if (id != null && value is Map<String, dynamic>) {
            _mem[id] = ItemMeta(
              id: id,
              name: (value['name'] as String?) ?? 'Item $id',
              iconUrl: (value['icon'] as String?) ?? '',
              accountBound: (value['accountBound'] as bool?) ?? false,
              noSell: (value['noSell'] as bool?) ?? false,
              soulbindOnAcquire:
                  (value['soulbindOnAcquire'] as bool?) ?? false,
              rarity: (value['rarity'] as String?) ?? '',
              type: (value['type'] as String?) ?? '',
            );
          }
        });
      }
    } catch (_) {
      // Corrupt cache: drop it and refetch lazily.
      _mem.clear();
    }
  }

  ItemMeta lookup(int id) {
    _ensureLoaded();
    return _mem[id] ?? ItemMeta.unknown(id);
  }

  /// Fetches metadata for ids missing from the cache, then persists.
  Future<void> warm(
    Set<int> ids,
    Future<Map<int, ItemMeta>> Function(List<int> ids) fetch,
  ) async {
    _ensureLoaded();
    final missing = ids.where((id) => !_mem.containsKey(id)).toList();
    if (missing.isEmpty) return;
    try {
      final fetched = await fetch(missing);
      if (fetched.isEmpty) return;
      _mem.addAll(fetched);
      _schedulePersist();
    } catch (_) {
      // Metadata is a nicety; a failed fetch must not fail the sync.
    }
  }

  /// Coalesces bursts of warm() calls into a single delayed write: each
  /// persist is a full MB-scale jsonEncode + prefs write.
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () async {
      final map = <String, dynamic>{
        for (final e in _mem.entries) '${e.key}': e.value.toJson(),
      };
      try {
        await _prefs.setString(_prefsKey, jsonEncode(map));
      } catch (_) {
        // Cache too large or disk hiccup: keep the in-memory copy.
      }
    });
  }
}
