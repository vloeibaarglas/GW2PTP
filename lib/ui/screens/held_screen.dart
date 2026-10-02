/// Deliveries screen: the delivery box and recent fills, tabbed like Listings.
///
/// "Sold" lists recently filled sells with their timestamps plus the coins
/// still waiting for pickup; "Bought" is items waiting for pickup from
/// filled buys.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import '../../util/coins.dart';
import '../../util/time_ago.dart';
import '../widgets/coins_text.dart';
import '../widgets/item_tile.dart';
import '../widgets/range_selector.dart';

class HeldScreen extends StatelessWidget {
  const HeldScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [
            Tab(text: 'Sold'),
            Tab(text: 'Bought'),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _SoldTab(),
                _BoughtTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoughtTab extends StatefulWidget {
  const _BoughtTab();

  @override
  State<_BoughtTab> createState() => _BoughtTabState();
}

class _BoughtTabState extends State<_BoughtTab> {
  /// Key of the row whose subtitle is expanded to full text; null when none.
  /// Tapping a row toggles it (single-expanded).
  String? _expandedRowKey;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.boughtHistory;
    final items = state.delivery.items;
    final theme = Theme.of(context);

    final boughtTotal = history.fold<int>(0, (sum, t) => sum + t.totalValue);

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Group By', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<HistoryGrouping>(
            segments: const [
              ButtonSegment(
                  value: HistoryGrouping.txn, label: Text('By Txn')),
              ButtonSegment(
                  value: HistoryGrouping.item, label: Text('By Item')),
              ButtonSegment(
                  value: HistoryGrouping.price, label: Text('By Price')),
            ],
            selected: {state.boughtGrouping},
            onSelectionChanged: (s) => state.setBoughtGrouping(s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          Text('Range', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          HistoryRangeSelector(
            current: state.boughtRange,
            onChanged: state.setBoughtRange,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Bought Value'),
                        CoinsText(
                          boughtTotal,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._historyRows(
            history: history,
            grouping: state.boughtGrouping,
            expandedRowKey: _expandedRowKey,
            onToggleRow: (key) => setState(
                () => _expandedRowKey = _expandedRowKey == key ? null : key),
            metaLookup: state.meta.lookup,
            fillsNoun: 'buys',
            capped: state.boughtHistoryCapped,
            emptyText: 'No recent purchases.',
          ),
          const SizedBox(height: 8),
          Text('Waiting For Pickup', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No items waiting for pickup.')),
            ),
          for (final item in items)
            Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ItemTile(
                itemId: item.itemId,
                metaLookup: state.meta.lookup,
                subtitle: Text(
                  '×${item.count}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One rendered row of sold history after grouping.
class HistoryRow {
  final int itemId;
  final int quantity;
  final int price; // unit price: exact for txn/price, weighted avg for item
  final int total;
  final DateTime? filledAt; // latest fill in the group
  final int sales; // transactions collapsed into this row

  const HistoryRow({
    required this.itemId,
    required this.quantity,
    required this.price,
    required this.total,
    required this.filledAt,
    required this.sales,
  });
}

HistoryRow _collapse(List<TpTransaction> group) {
  final first = group.first;
  final quantity = group.fold<int>(0, (sum, t) => sum + t.quantity);
  final total = group.fold<int>(0, (sum, t) => sum + t.totalValue);
  DateTime? latest;
  for (final t in group) {
    final f = t.filledAt;
    if (f != null && (latest == null || f.isAfter(latest))) latest = f;
  }
  return HistoryRow(
    itemId: first.itemId,
    quantity: quantity,
    price: quantity == 0 ? 0 : total ~/ quantity,
    total: total,
    filledAt: latest,
    sales: group.length,
  );
}

/// Groups sold history per [mode], preserving first-appearance order.
List<HistoryRow> groupHistory(List<TpTransaction> history, HistoryGrouping mode) {
  switch (mode) {
    case HistoryGrouping.txn:
      return [
        for (final t in history)
          HistoryRow(
            itemId: t.itemId,
            quantity: t.quantity,
            price: t.price,
            total: t.totalValue,
            filledAt: t.filledAt,
            sales: 1,
          ),
      ];
    case HistoryGrouping.price:
      final byKey = <String, List<TpTransaction>>{};
      for (final t in history) {
        byKey.putIfAbsent('${t.itemId}@${t.price}', () => []).add(t);
      }
      return [for (final g in byKey.values) _collapse(g)];
    case HistoryGrouping.item:
      final byItem = <int, List<TpTransaction>>{};
      for (final t in history) {
        byItem.putIfAbsent(t.itemId, () => []).add(t);
      }
      return [for (final g in byItem.values) _collapse(g)];
  }
}

/// Stable identity for a rendered history row so the expanded state follows
/// the row (not its position) across rebuilds.
String _historyRowKey(HistoryRow r) =>
    '${r.itemId}|${r.price}|${r.quantity}|${r.filledAt?.toIso8601String()}';

/// One-line (or fully expanded) subtitle for a history row. [fillsNoun] is
/// 'sales' on the Sold tab, 'buys' on the Bought tab.
Widget _historyRowSubtitle(
    HistoryRow r, bool expanded, HistoryGrouping grouping, String fillsNoun) {
  final ago = timeAgo(r.filledAt);
  final when = ago.isEmpty ? '' : ' · $ago';
  final countNote = r.sales > 1 ? ' · ${r.sales} $fillsNoun' : '';
  final avgNote =
      grouping == HistoryGrouping.item && r.sales > 1 ? ' avg' : '';
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: '×${r.quantity} @ '),
      ...coinSpans(r.price),
      TextSpan(text: avgNote),
      const TextSpan(text: ' · '),
      ...coinSpans(r.total),
      TextSpan(text: '$countNote$when'),
    ]),
    maxLines: expanded ? null : 1,
    overflow: expanded ? null : TextOverflow.ellipsis,
  );
}

/// Grouped history rows with tap-to-expand subtitles and the 2,000-row cap
/// footer, as a widget list to spread directly into the tab's ListView.
/// Shared by the Sold and Bought tabs so both offer the same interface.
/// (HistoryGrouping lives in app_state.dart.)
///
/// These must stay a flat list, NOT a Column widget: a Column is a single
/// sliver child and defeats the ListView's lazy building, forcing all rows
/// (up to 2,000 cards with icons) to build and lay out on every tap — that
/// is what made the Bought tab's buttons laggy. Spread rows stay lazy.
List<Widget> _historyRows({
  required List<TpTransaction> history,
  required HistoryGrouping grouping,
  required String? expandedRowKey,
  required ValueChanged<String> onToggleRow,
  required ItemMeta Function(int id) metaLookup,
  required String fillsNoun,
  required bool capped,
  required String emptyText,
}) {
  final rows = groupHistory(history, grouping);
  return [
    if (history.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(emptyText)),
      ),
    for (final row in rows)
      Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: ItemTile(
          itemId: row.itemId,
          metaLookup: metaLookup,
          subtitle: _historyRowSubtitle(
              row, expandedRowKey == _historyRowKey(row), grouping, fillsNoun),
          clipSubtitle: expandedRowKey != _historyRowKey(row),
          onTap: () => onToggleRow(_historyRowKey(row)),
        ),
      ),
    if (capped)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('Showing 2,000 Most Recent Transactions'),
        ),
      ),
  ];
}

class _SoldTab extends StatefulWidget {
  const _SoldTab();

  @override
  State<_SoldTab> createState() => _SoldTabState();
}

class _SoldTabState extends State<_SoldTab> {
  /// Key of the row whose subtitle is expanded to full text; null when none.
  /// Tapping a row toggles it (single-expanded).
  String? _expandedRowKey;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.soldHistory;
    final theme = Theme.of(context);

    final gross = history.fold<int>(0, (sum, t) => sum + t.totalValue);

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Group By', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<HistoryGrouping>(
            segments: const [
              ButtonSegment(
                  value: HistoryGrouping.txn, label: Text('By Txn')),
              ButtonSegment(
                  value: HistoryGrouping.item, label: Text('By Item')),
              ButtonSegment(
                  value: HistoryGrouping.price, label: Text('By Price')),
            ],
            selected: {state.soldGrouping},
            onSelectionChanged: (s) => state.setSoldGrouping(s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          Text('Range', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          HistoryRangeSelector(
            current: state.soldRange,
            onChanged: state.setSoldRange,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Listed Value'),
                        CoinsText(
                          gross,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Net Value'),
                        CoinsText(
                          netOfFees(gross),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              dense: true,
              leading: Image.asset(
                'assets/images/coin_gold.png',
                width: 40,
                height: 40,
              ),
              title: const Text('Coins Waiting For Pickup'),
              subtitle: CoinsText(
                state.delivery.coins,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._historyRows(
            history: history,
            grouping: state.soldGrouping,
            expandedRowKey: _expandedRowKey,
            onToggleRow: (key) => setState(
                () => _expandedRowKey = _expandedRowKey == key ? null : key),
            metaLookup: state.meta.lookup,
            fillsNoun: 'sales',
            capped: state.soldHistoryCapped,
            emptyText: 'No recent sales.',
          ),
        ],
      ),
    );
  }
}
