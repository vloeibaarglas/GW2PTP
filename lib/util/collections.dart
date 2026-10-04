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
