/// App-level summary: highlight tiles from every section plus recent
/// fills, derived from the already-loaded state — no new data pull.
/// Tapping a tile jumps to the bottom tab it summarizes. Tab indices
/// must match HomeScreen's order: 0 Summary, 1 Listings, 2 Deliveries,
/// 3 Holdings.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../util/coins.dart';
import '../../util/time_ago.dart';
import '../widgets/coins_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/item_tile.dart';

class SummaryScreen extends StatelessWidget {
  /// Jumps to a bottom tab by index (see the order note above).
  final void Function(int index) onNavigate;

  const SummaryScreen({super.key, required this.onNavigate});

  static const listingsTab = 1;
  static const deliveriesTab = 2;
  static const holdingsTab = 3;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    bool inWindow(t, Duration window) =>
        t.filledAt != null && now.difference(t.filledAt!) < window;
    final sold24h = state.soldHistory
        .where((t) => inWindow(t, const Duration(days: 1)));
    final sold7d = state.soldHistory
        .where((t) => inWindow(t, const Duration(days: 7)));
    final bought24h = state.boughtHistory
        .where((t) => inWindow(t, const Duration(days: 1)));
    final listedValue =
        state.sells.fold<int>(0, (sum, o) => sum + o.totalValue);
    final sold24hValue =
        sold24h.fold<int>(0, (sum, t) => sum + t.totalValue);
    final sold7dValue = sold7d.fold<int>(0, (sum, t) => sum + t.totalValue);
    final bought24hValue =
        bought24h.fold<int>(0, (sum, t) => sum + t.totalValue);
    final pickupCount =
        state.delivery.items.fold<int>(0, (sum, i) => sum + i.count);
    final inventoryUnits =
        state.inventory.fold<int>(0, (sum, i) => sum + i.count);
    // soldHistory arrives newest-first from the API walk, so the first
    // entries are the recent fills — no re-sort on every build.
    final recentFills =
        state.soldHistory.where((t) => t.filledAt != null).take(4).toList();
    final empty = state.sells.isEmpty &&
        state.buys.isEmpty &&
        state.soldHistory.isEmpty &&
        state.boughtHistory.isEmpty &&
        state.delivery.items.isEmpty &&
        state.delivery.coins == 0 &&
        state.inventory.isEmpty;

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (empty)
            const EmptyState('Nothing to summarize yet — pull to refresh.')
          else ...[
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Listed value',
                    copper: listedValue,
                    onTap: () => onNavigate(listingsTab),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryTile(
                    label: 'Net value',
                    copper: netOfFees(listedValue),
                    onTap: () => onNavigate(listingsTab),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Open orders',
                    count: state.sells.length + state.buys.length,
                    onTap: () => onNavigate(listingsTab),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryTile(
                    label: 'To pick up',
                    copper: state.delivery.coins,
                    subline: '$pickupCount items',
                    onTap: () => onNavigate(deliveriesTab),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Sold · 24h',
                    copper: sold24hValue,
                    subline: '${sold24h.length} fills',
                    onTap: () => onNavigate(deliveriesTab),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryTile(
                    label: 'Sold · 7d',
                    copper: sold7dValue,
                    subline: '${sold7d.length} fills',
                    onTap: () => onNavigate(deliveriesTab),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Inventory',
                    count: inventoryUnits,
                    subline: '${state.inventory.length} types',
                    onTap: () => onNavigate(holdingsTab),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryTile(
                    label: 'Bought · 24h',
                    copper: bought24hValue,
                    subline: '${bought24h.length} purchases',
                    onTap: () => onNavigate(deliveriesTab),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Recent fills',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (recentFills.isEmpty)
              const EmptyState('No recent sales.')
            else
              for (final t in recentFills)
                Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ItemTile(
                    itemId: t.itemId,
                    metaLookup: state.meta.lookup,
                    subtitle: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'sold '),
                        ...coinSpans(t.totalValue),
                        TextSpan(text: ' · ${timeAgo(t.filledAt)}'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// One summary tile: a label, a big value (coins or a count), and an
/// optional subline. Tapping jumps to the bottom tab it summarizes.
class _SummaryTile extends StatelessWidget {
  final String label;
  final int? copper;
  final int? count;
  final String? subline;
  final VoidCallback? onTap;

  const _SummaryTile({
    required this.label,
    this.copper,
    this.count,
    this.subline,
    this.onTap,
  }) : assert(copper != null || count != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              if (copper != null)
                CoinsText(copper!, style: theme.textTheme.headlineSmall)
              else
                Text('$count', style: theme.textTheme.headlineSmall),
              if (subline != null) Text(subline!),
            ],
          ),
        ),
      ),
    );
  }
}
