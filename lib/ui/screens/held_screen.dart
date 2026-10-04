/// Deliveries screen: the delivery box and recent fills, tabbed like Listings.
///
/// "Sold" lists recently filled sells with their timestamps plus the coins
/// still waiting for pickup; "Bought" is items waiting for pickup from
/// filled buys.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/gw2_client.dart';
import '../../api/models.dart';
import '../../state/app_state.dart';
import '../../util/coins.dart';
import '../../util/collections.dart';
import '../../util/day_label.dart';
import '../../util/numbers.dart';
import '../../util/time_ago.dart';
import '../widgets/coins_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/item_tile.dart';
import '../widgets/history_filters.dart';
import '../widgets/notice_banner.dart';
import '../widgets/range_selector.dart';
import '../widgets/value_tile.dart';

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

  /// Memoized grouped view: regroups only when the history instance or
  /// grouping changes (see [_GroupedHistoryView]).
  final _view = _GroupedHistoryView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.boughtHistory;
    final items = state.delivery.items;
    final theme = Theme.of(context);

    final boughtTotal = _view.totalFor(history, state.boughtGrouping);
    final pickupMode = state.boughtMode == BoughtMode.pickup;

    // In pickup mode the history controls stay visible but greyed out and
    // uninteractable — they only apply to the historical record.
    Widget historyControls(Widget child) => pickupMode
        ? IgnorePointer(
            ignoring: true,
            child: Opacity(opacity: 0.38, child: child),
          )
        : child;

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<BoughtMode>(
            style: compactSegmentedStyle,
            segments: const [
              ButtonSegment(value: BoughtMode.pickup, label: Text('Pickup')),
              ButtonSegment(value: BoughtMode.history, label: Text('History')),
            ],
            selected: {state.boughtMode},
            onSelectionChanged: (s) => state.setBoughtMode(s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          historyControls(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HistoryFilters(
                  grouping: state.boughtGrouping,
                  onGroupingChanged: state.setBoughtGrouping,
                  range: state.boughtRange,
                  onRangeChanged: state.setBoughtRange,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (!pickupMode && state.boughtHistoryTruncated)
            _capWarningTile(state.boughtHistoryCoveredSince),
          historyControls(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueTile(
                  labels: const ['Bought Value'],
                  copperValues: [boughtTotal],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (pickupMode) ...[
            Text('Waiting For Pickup', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (items.isEmpty)
              const EmptyState('No items waiting for pickup.'),
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
          ] else
            ..._historyRows(
              rows: _view.rowsFor(history, state.boughtGrouping),
              isEmpty: history.isEmpty,
              grouping: state.boughtGrouping,
              expandedRowKey: _expandedRowKey,
              onToggleRow: (key) => setState(
                  () => _expandedRowKey = _expandedRowKey == key ? null : key),
              metaLookup: state.meta.lookup,
              fillsNoun: 'buys',
              capped: state.boughtHistoryTruncated,
              emptyText: 'No recent purchases.',
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
      final byKey = groupByKey(history, (t) => '${t.itemId}@${t.price}');
      return [for (final g in byKey.values) _collapse(g)];
    case HistoryGrouping.item:
      final byItem = groupByKey(history, (t) => t.itemId);
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

/// "25,000" for the history cap: AppState.historyMaxPages × 200 rows per
/// page. Computed, not hardcoded, so the footer and warning tile track the
/// cap if it ever changes.
String _capCountLabel() =>
    commas(AppState.historyMaxPages * Gw2Api.historyPageSize);

/// "Sep 14, 2026" in the device's local timezone, for the cap warning.
String _capDateLabel(DateTime dt) => dayLabel(dt);

/// Warning tile placed directly below the range selector when the history
/// fetch walked the full page cap without covering the selected window:
/// the totals only reflect the most recent [cap] transactions, back to
/// [coveredSince]. Rare by design — most users never see it.
Widget _capWarningTile(DateTime coveredSince) {
  return NoticeBanner(
    card: true,
    maxLines: null,
    icon: Icons.warning_amber_outlined,
    text: 'Showing the ${_capCountLabel()} most recent transactions, '
        'back to ${_capDateLabel(coveredSince)} — older activity in '
        'this range is not included.',
  );
}

/// Memoized grouped-history view for the Held tabs: regroups (and
/// re-totals) only when the history list instance or the grouping changes —
/// not on every build. At 25k rows a regroup costs multiple full passes,
/// so row expand taps must not pay it. Follows the inventory screen's
/// identical() memo pattern; the AppState history getters return a stable
/// instance across rebuilds, which is what makes the identity check work.
class _GroupedHistoryView {
  List<TpTransaction>? _history;
  HistoryGrouping? _grouping;
  List<HistoryRow>? _rows;
  int _total = 0;

  /// Grouped rows for [history] under [grouping].
  List<HistoryRow> rowsFor(List<TpTransaction> history, HistoryGrouping grouping) {
    _refresh(history, grouping);
    return _rows!;
  }

  /// Sum of totalValue over [history].
  int totalFor(List<TpTransaction> history, HistoryGrouping grouping) {
    _refresh(history, grouping);
    return _total;
  }

  void _refresh(List<TpTransaction> history, HistoryGrouping grouping) {
    if (identical(history, _history) && grouping == _grouping) return;
    _history = history;
    _grouping = grouping;
    _rows = groupHistory(history, grouping);
    _total = history.fold<int>(0, (sum, t) => sum + t.totalValue);
  }
}

/// Grouped history rows with tap-to-expand subtitles and the 25,000-row cap
/// footer, as a widget list to spread directly into the tab's ListView.
/// Shared by the Sold and Bought tabs so both offer the same interface.
/// (HistoryGrouping lives in app_state.dart.)
///
/// These must stay a flat list, NOT a Column widget: a Column is a single
/// sliver child and defeats the ListView's lazy building, forcing all rows
/// (up to 25,000 cards with icons) to build and lay out on every tap — that
/// is what made the Bought tab's buttons laggy. Spread rows stay lazy.
List<Widget> _historyRows({
  required List<HistoryRow> rows,
  required bool isEmpty,
  required HistoryGrouping grouping,
  required String? expandedRowKey,
  required ValueChanged<String> onToggleRow,
  required ItemMeta Function(int id) metaLookup,
  required String fillsNoun,
  required bool capped,
  required String emptyText,
}) {
  return [
    if (isEmpty) EmptyState(emptyText),
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
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('Showing ${_capCountLabel()} Most Recent Transactions'),
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

  /// Memoized grouped view (see [_GroupedHistoryView]).
  final _view = _GroupedHistoryView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.soldHistory;
    final theme = Theme.of(context);

    final gross = _view.totalFor(history, state.soldGrouping);

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HistoryFilters(
            grouping: state.soldGrouping,
            onGroupingChanged: state.setSoldGrouping,
            range: state.soldRange,
            onRangeChanged: state.setSoldRange,
          ),
          const SizedBox(height: 8),
          if (state.soldHistoryTruncated)
            _capWarningTile(state.soldHistoryCoveredSince),
          ValueTile(
            labels: const ['Sold Value', 'Net Value'],
            copperValues: [gross, netOfFees(gross)],
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
            rows: _view.rowsFor(history, state.soldGrouping),
            isEmpty: history.isEmpty,
            grouping: state.soldGrouping,
            expandedRowKey: _expandedRowKey,
            onToggleRow: (key) => setState(
                () => _expandedRowKey = _expandedRowKey == key ? null : key),
            metaLookup: state.meta.lookup,
            fillsNoun: 'sales',
            capped: state.soldHistoryTruncated,
            emptyText: 'No recent sales.',
          ),
        ],
      ),
    );
  }
}
