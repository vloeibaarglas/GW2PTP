/// Compact label-less segmented control shared by the history tabs'
/// Group By and the Listings tab's grouping: 12sp labels, tightened
/// padding, dense — one consistent filter style everywhere.
library;

import 'package:flutter/material.dart';

import 'range_selector.dart' show compactSegmentedStyle;

class CompactGroupBy<T> extends StatelessWidget {
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  const CompactGroupBy({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      style: compactSegmentedStyle,
      segments: [
        for (final v in values)
          ButtonSegment(value: v, label: Text(labelOf(v))),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}
