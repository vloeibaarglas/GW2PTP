/// Compact filter bar shared by the Sold and Bought tabs: one row of
/// dropdown chips (time window, grouping, sort) instead of three stacked
/// segmented rows. Each chip shows its current value; tapping opens a
/// bottom sheet with the options and a one-line explanation each.
library;

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'filter_dropdown_chip.dart';
import 'range_selector.dart';

String _groupingLabel(HistoryGrouping g) => switch (g) {
      HistoryGrouping.txn => 'By Txn',
      HistoryGrouping.item => 'By Item',
      HistoryGrouping.price => 'By Price',
    };

String _sortLabel(HistorySort s) => switch (s) {
      HistorySort.dateDesc => 'Newest',
      HistorySort.priceDesc => 'Price ↓',
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
    return Row(
      children: [
        Expanded(
          child: _RangeChip(range: range, onRangeChanged: onRangeChanged),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilterDropdownChip<HistoryGrouping>(
            icon: Icons.view_list,
            currentLabel: _groupingLabel(grouping),
            sheetTitle: 'Group rows',
            options: const [
              FilterOption(
                value: HistoryGrouping.txn,
                label: 'By Txn',
                description: 'Every fill on its own row',
              ),
              FilterOption(
                value: HistoryGrouping.item,
                label: 'By Item',
                description: 'One row per item, weighted-average price',
              ),
              FilterOption(
                value: HistoryGrouping.price,
                label: 'By Price',
                description: 'One row per price point',
              ),
            ],
            selected: grouping,
            onChanged: onGroupingChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilterDropdownChip<HistorySort>(
            icon: Icons.sort,
            currentLabel: _sortLabel(sort),
            sheetTitle: 'Sort rows',
            options: const [
              FilterOption(
                value: HistorySort.dateDesc,
                label: 'Newest',
                description: 'Latest fills first',
              ),
              FilterOption(
                value: HistorySort.priceDesc,
                label: 'Price ↓',
                description: 'Highest unit price first',
              ),
            ],
            selected: sort,
            onChanged: onSortChanged,
          ),
        ),
      ],
    );
  }
}

/// Time-window chip: its sheet hosts the existing [HistoryRangeSelector]
/// (hour presets plus the rotary day dial) verbatim.
class _RangeChip extends StatelessWidget {
  final HistoryRange range;
  final Future<void> Function(HistoryRange) onRangeChanged;

  const _RangeChip({required this.range, required this.onRangeChanged});

  @override
  Widget build(BuildContext context) {
    return FilterChipShell(
      icon: Icons.schedule,
      label: range.label,
      onTap: () => _openSheet(context),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Time window',
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              HistoryRangeSelector(
                current: range,
                onChanged: (r) async {
                  Navigator.of(sheetContext).pop();
                  await onRangeChanged(r);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
