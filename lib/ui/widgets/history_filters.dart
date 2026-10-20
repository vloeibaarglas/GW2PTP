/// Compact Group By + Range + Sort filters shared by the Sold and Bought
/// tabs: no text labels (the segments are self-explanatory), small dense
/// segments, tight spacing — one consistent filter element everywhere.
library;

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'compact_group_by.dart';
import 'range_selector.dart';

String _groupingLabel(HistoryGrouping g) => switch (g) {
      HistoryGrouping.txn => 'By Txn',
      HistoryGrouping.item => 'By Item',
      HistoryGrouping.price => 'By Price',
    };

String _sortLabel(HistorySort s) => switch (s) {
      HistorySort.dateDesc => 'Newest',
      HistorySort.dateAsc => 'Oldest',
      HistorySort.priceDesc => 'Price ↓',
      HistorySort.priceAsc => 'Price ↑',
    };

class HistoryFilters extends StatelessWidget {
  final HistoryGrouping grouping;
  final ValueChanged<HistoryGrouping> onGroupingChanged;
  final HistoryRange range;
  final Future<void> Function(HistoryRange) onRangeChanged;
  final HistorySort sort;
  final ValueChanged<HistorySort> onSortChanged;

  const HistoryFilters({
    super.key,
    required this.grouping,
    required this.onGroupingChanged,
    required this.range,
    required this.onRangeChanged,
    required this.sort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompactGroupBy<HistoryGrouping>(
          values: HistoryGrouping.values,
          labelOf: _groupingLabel,
          selected: grouping,
          onChanged: onGroupingChanged,
        ),
        const SizedBox(height: 6),
        HistoryRangeSelector(
          current: range,
          onChanged: onRangeChanged,
        ),
        const SizedBox(height: 6),
        CompactGroupBy<HistorySort>(
          values: HistorySort.values,
          labelOf: _sortLabel,
          selected: sort,
          onChanged: onSortChanged,
        ),
      ],
    );
  }
}
