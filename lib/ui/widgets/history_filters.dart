/// Compact Group By + Range filters shared by the Sold and Bought tabs:
/// no text labels (the segments are self-explanatory), small dense
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

class HistoryFilters extends StatelessWidget {
  final HistoryGrouping grouping;
  final ValueChanged<HistoryGrouping> onGroupingChanged;
  final HistoryRange range;
  final Future<void> Function(HistoryRange) onRangeChanged;

  const HistoryFilters({
    super.key,
    required this.grouping,
    required this.onGroupingChanged,
    required this.range,
    required this.onRangeChanged,
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
      ],
    );
  }
}
