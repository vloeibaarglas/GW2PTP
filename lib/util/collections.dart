/// Small collection helpers shared across the app.
library;

/// Groups [items] by [keyOf], preserving first-appearance key order.
/// Backs the history and listings grouping (by item, by item@price).
Map<K, List<T>> groupByKey<T, K>(List<T> items, K Function(T) keyOf) {
  final groups = <K, List<T>>{};
  for (final item in items) {
    groups.putIfAbsent(keyOf(item), () => []).add(item);
  }
  return groups;
}

/// One collapsed row per [keyOf] group: groups preserving first-appearance
/// order, then maps each group through [collapse]. Backs the price/item
/// modes of the history and open-orders grouping controls.
List<R> collapseByKey<T, K, R>(
  List<T> items,
  K Function(T) keyOf,
  R Function(List<T> group) collapse,
) =>
    [for (final g in groupByKey(items, keyOf).values) collapse(g)];
