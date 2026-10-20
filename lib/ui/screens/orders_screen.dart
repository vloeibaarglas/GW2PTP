/// Listings screen: open buy/sell orders valued at their listed prices.
///
/// Buys show the order value at the bid; sells show the ask and the net
/// proceeds after the 15% Trading Post cut. The listed price is the
/// valuation — no market ping needed.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import '../../util/coins.dart';
import '../../util/collections.dart';
import '../widgets/coins_text.dart';
import '../widgets/compact_group_by.dart';
import '../widgets/empty_state.dart';
import '../widgets/item_tile.dart';
import '../widgets/value_tile.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [
            Tab(text: 'Selling'),
            Tab(text: 'Buying'),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _OrderList(side: 'sell'),
                _OrderList(side: 'buy'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final String side;

  const _OrderList({required this.side});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final orders = side == 'buy' ? state.buys : state.sells;
    final grouping =
        side == 'buy' ? state.buyingGrouping : state.sellingGrouping;
    final setGrouping =
        side == 'buy' ? state.setBuyingGrouping : state.setSellingGrouping;
    final sort = side == 'buy' ? state.buyingSort : state.sellingSort;
    final setSort = side == 'buy' ? state.setBuyingSort : state.setSellingSort;

    final total = orders.fold<int>(0, (sum, o) => sum + o.totalValue);
    final rows = sortOrderRows(groupOrders(orders, grouping), sort);

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CompactGroupBy<OrderGrouping>(
            values: OrderGrouping.values,
            labelOf: (g) => g.label,
            selected: grouping,
            onChanged: setGrouping,
          ),
          const SizedBox(height: 8),
          CompactGroupBy<OrderSort>(
            values: OrderSort.values,
            labelOf: (s) => s.label,
            selected: sort,
            onChanged: setSort,
          ),
          const SizedBox(height: 8),
          ValueTile(
            labels: [
              side == 'buy' ? 'Order Value' : 'Listed Value',
              if (side == 'sell') 'Net Value',
            ],
            copperValues: [
              total,
              if (side == 'sell') netOfFees(total),
            ],
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            EmptyState(
              side == 'buy' ? 'No open buy orders.' : 'No open sell orders.',
            ),
          for (final row in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ItemTile(
                itemId: row.itemId,
                metaLookup: state.meta.lookup,
                subtitle: _subtitle(row, grouping),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subtitle(OrderRow row, OrderGrouping grouping) {
    final spans = <InlineSpan>[
      TextSpan(text: '×${row.quantity} @ '),
      ...coinSpans(row.price),
    ];
    if (row.orders > 1) {
      spans.add(TextSpan(
          text: grouping == OrderGrouping.item ? ' avg' : ' · ${row.orders} orders'));
    }
    spans.add(const TextSpan(text: ' · '));
    if (side == 'buy') {
      spans.addAll([
        const TextSpan(text: 'Order Value '),
        ...coinSpans(row.total),
      ]);
    } else {
      spans.addAll([
        const TextSpan(text: 'Net '),
        ...coinSpans(netOfFees(row.total)),
      ]);
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// One rendered listings row after grouping.
class OrderRow {
  final int itemId;
  final int quantity;
  final int price; // unit price: exact for order/price, weighted avg for item
  final int total;
  final int orders; // open orders collapsed into this row

  const OrderRow({
    required this.itemId,
    required this.quantity,
    required this.price,
    required this.total,
    required this.orders,
  });
}

/// Orders grouped listing rows per [sort]: highest unit price first, or
/// the exchange's listing order untouched.
List<OrderRow> sortOrderRows(List<OrderRow> rows, OrderSort sort) {
  if (sort == OrderSort.listed) return rows;
  final ordered = [...rows];
  ordered.sort((a, b) => b.price.compareTo(a.price));
  return ordered;
}

/// Groups open orders per [mode], preserving first-appearance order.
List<OrderRow> groupOrders(List<TpOrder> orders, OrderGrouping mode) {
  OrderRow collapse(List<TpOrder> group) {
    final first = group.first;
    final quantity = group.fold<int>(0, (sum, o) => sum + o.quantity);
    final total = group.fold<int>(0, (sum, o) => sum + o.totalValue);
    return OrderRow(
      itemId: first.itemId,
      quantity: quantity,
      price: quantity == 0 ? 0 : total ~/ quantity,
      total: total,
      orders: group.length,
    );
  }

  switch (mode) {
    case OrderGrouping.order:
      return [
        for (final o in orders)
          OrderRow(
            itemId: o.itemId,
            quantity: o.quantity,
            price: o.price,
            total: o.totalValue,
            orders: 1,
          ),
      ];
    case OrderGrouping.price:
      return collapseByKey(orders, (o) => '${o.itemId}@${o.price}', collapse);
    case OrderGrouping.item:
      return collapseByKey(orders, (o) => o.itemId, collapse);
  }
}
