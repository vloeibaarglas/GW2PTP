/// In-memory-only cache for item details pages.
///
/// Design contract (per the feature spec):
/// - Fetch on open only: nothing is prefetched, warmed, or synced.
/// - An opened item's data is cached for 60 seconds to prevent rapid
///   reloads (re-opening, or pull-to-refresh within the window).
/// - Nothing persists to disk: entries live and die with the process.
/// - Stale entries are refetched wholesale, including any on-demand
///   sections (order book, history) already loaded.
library;

import 'dart:async';

import '../api/gw2_client.dart';
import '../api/models.dart';

/// Everything the details page renders. Phase-1 fields (detail, quote,
/// recipes) load together on open; [book] and [history] fill in on demand
/// afterwards and ride along in the same cache entry.
class ItemDetailBundle {
  final ItemDetail detail;
  final CommerceQuote? quote;
  final List<CraftRecipe> recipes;

  /// Full order book; null until the user taps "load full depth".
  ListingBook? book;

  /// gw2bltc history; null until the background fetch completes.
  List<PricePoint>? history;

  ItemDetailBundle({
    required this.detail,
    required this.quote,
    required this.recipes,
  });
}

class _Entry {
  final ItemDetailBundle bundle;
  final DateTime loadedAt;
  _Entry(this.bundle, this.loadedAt);
}

class ItemDetailCache {
  /// Time-to-live for an opened item: re-opens inside the window reuse
  /// the entry, older entries refetch.
  static const ttl = Duration(seconds: 60);

  final Map<int, _Entry> _mem = {};
  final Map<int, Future<ItemDetailBundle>> _inflight = {};

  /// Phase-1 bundle for [id]: full item record + top-of-book quote +
  /// craft recipes, fetched concurrently. Returns the cached bundle when
  /// fresh; concurrent callers for the same id share one fetch.
  Future<ItemDetailBundle> get(int id, Gw2Api api) {
    final now = DateTime.now();
    final hit = _mem[id];
    if (hit != null && now.difference(hit.loadedAt) < ttl) {
      return Future.value(hit.bundle);
    }
    return _inflight.putIfAbsent(id, () async {
      try {
        final fetched = await Future.wait([
          api.fetchItemDetail(id),
          api.fetchCommercePrices(id),
          _fetchRecipes(api, id),
        ]);
        final bundle = ItemDetailBundle(
          detail: ItemDetail.fromJson(fetched[0] as Map<String, dynamic>),
          quote: fetched[1] as CommerceQuote?,
          recipes: fetched[2] as List<CraftRecipe>,
        );
        _mem[id] = _Entry(bundle, DateTime.now());
        return bundle;
      } finally {
        _inflight.remove(id);
      }
    });
  }

  /// Full order book for [id], on demand. Requires a fresh phase-1 entry;
  /// throws [StateError] when the page was never opened (or expired), so
  /// callers cannot use the book path as a prefetch.
  Future<ListingBook?> book(int id, Gw2Api api) async {
    final entry = _fresh(id);
    if (entry.bundle.book != null) return entry.bundle.book;
    final book = await api.fetchListings(id);
    // Re-check freshness: a slow book fetch must not resurrect an entry
    // that expired (and was possibly replaced) while it was in flight.
    final current = _freshOrNull(id);
    if (current == null || !identical(current, entry)) return book;
    entry.bundle.book = book;
    return book;
  }

  /// gw2bltc history for [id], loaded in the background after open.
  /// Same freshness contract as [book].
  Future<List<PricePoint>> history(int id, Gw2Api api) async {
    final entry = _fresh(id);
    if (entry.bundle.history != null) return entry.bundle.history!;
    final history = await api.fetchPriceHistory(id);
    final current = _freshOrNull(id);
    if (current == null || !identical(current, entry)) return history;
    entry.bundle.history = history;
    return history;
  }

  /// Ingredient top-of-book prices for a recipe, batched in one call.
  Future<Map<int, CommerceQuote>> ingredientPrices(
    List<int> ids,
    Gw2Api api,
  ) async {
    final result = <int, CommerceQuote>{};
    if (ids.isEmpty) return result;
    final fetched = await Future.wait(ids.map(api.fetchCommercePrices));
    for (var i = 0; i < ids.length; i++) {
      final q = fetched[i];
      if (q != null) result[ids[i]] = q;
    }
    return result;
  }

  /// Drops [id] so the next open refetches (pull-to-refresh).
  void invalidate(int id) {
    _mem.remove(id);
  }

  /// Test hook: is [id] currently cached and fresh?
  bool isFresh(int id) => _freshOrNull(id) != null;

  _Entry _fresh(int id) {
    final entry = _freshOrNull(id);
    if (entry == null) {
      throw StateError('No fresh details entry for item $id');
    }
    return entry;
  }

  _Entry? _freshOrNull(int id) {
    final entry = _mem[id];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.loadedAt) >= ttl) {
      _mem.remove(id);
      return null;
    }
    return entry;
  }

  Future<List<CraftRecipe>> _fetchRecipes(Gw2Api api, int id) async {
    try {
      final ids = await api.fetchRecipeIdsForOutput(id);
      if (ids.isEmpty) return const [];
      // First recipe only for v1: enough to show craftability + cost.
      final recipe = await api.fetchRecipe(ids.first);
      return recipe == null ? const [] : [recipe];
    } catch (_) {
      // Recipe data is a nicety; never fail the page for it.
      return const [];
    }
  }
}
