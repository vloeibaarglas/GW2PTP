/// Range selector for the history tabs: hour presets plus a rotary day
/// dial (1–30 days) that pops out of a calendar button.
///
/// Narrowing the range (or widening within cached coverage) stays a pure
/// local filter — the dial just produces a [HistoryRange], and the existing
/// instant-switch logic in AppState does the rest.
library;

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'day_dial.dart';

/// Compact segmented-button style shared by the history filters (and the
/// Bought tab's mode toggle): 14sp labels, tightened padding, dense —
/// ~20% fatter than the first compact pass, still slimmer than default.
final ButtonStyle compactSegmentedStyle = SegmentedButton.styleFrom(
  textStyle: const TextStyle(fontSize: 14),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  visualDensity: VisualDensity.compact,
);

class HistoryRangeSelector extends StatelessWidget {
  final HistoryRange current;
  final Future<void> Function(HistoryRange) onChanged;

  const HistoryRangeSelector({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dayCount = current.dayCount;
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<HistoryRange>(
            style: compactSegmentedStyle,
            segments: const [
              ButtonSegment(value: HistoryRange.h1, label: Text('1H')),
              ButtonSegment(value: HistoryRange.h6, label: Text('6H')),
              ButtonSegment(value: HistoryRange.h12, label: Text('12H')),
              ButtonSegment(value: HistoryRange.h24, label: Text('24H')),
            ],
            // Empty when a day-range from the dial is active.
            selected: {if (dayCount == null) current},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) => onChanged(s.first),
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(width: 8),
        if (dayCount != null)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _pick(context, dayCount),
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text('${dayCount}D'),
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _pick(context, 7),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('Days'),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, int initialDays) async {
    final picked =
        await showDayDialPicker(context, initialDays: initialDays);
    if (picked != null) await onChanged(HistoryRange.days(picked));
  }
}
