/// Compact inventory filters: Type and Rarity dropdowns plus tri-state
/// Sellable and Bound segmented controls. Dense — matches the history
/// filter style.
library;

import 'package:flutter/material.dart';

import 'compact_group_by.dart';

/// Canonical GW2 rarity order for the dropdown (only values present in
/// the inventory are shown).
const List<String> rarityOrder = [
  'Junk',
  'Basic',
  'Fine',
  'Masterwork',
  'Rare',
  'Exotic',
  'Ascended',
  'Legendary',
];

String _triLabel(bool? v) => v == null ? 'All' : (v ? 'Yes' : 'No');

/// Human-readable label for a GW2 API item type: "UpgradeComponent" becomes
/// "Upgrade Component". Only the display label is changed — filtering still
/// uses the raw API value.
String humanizeItemType(String type) =>
    type.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ');

class InventoryFilters extends StatelessWidget {
  final List<String> types;
  final List<String> rarities;
  final String? typeFilter;
  final String? rarityFilter;
  final bool? sellableFilter;
  final bool? boundFilter;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onRarityChanged;
  final ValueChanged<bool?> onSellableChanged;
  final ValueChanged<bool?> onBoundChanged;

  const InventoryFilters({
    super.key,
    required this.types,
    required this.rarities,
    required this.typeFilter,
    required this.rarityFilter,
    required this.sellableFilter,
    required this.boundFilter,
    required this.onTypeChanged,
    required this.onRarityChanged,
    required this.onSellableChanged,
    required this.onBoundChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.labelSmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<String?>(
                value: typeFilter,
                isExpanded: true,
                style: theme.textTheme.bodySmall,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Type: All'),
                  ),
                  for (final t in types)
                    DropdownMenuItem<String?>(value: t, child: Text(humanizeItemType(t))),
                ],
                onChanged: onTypeChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String?>(
                value: rarityFilter,
                isExpanded: true,
                style: theme.textTheme.bodySmall,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Rarity: All'),
                  ),
                  for (final r in rarities)
                    DropdownMenuItem<String?>(value: r, child: Text(r)),
                ],
                onChanged: onRarityChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sellable', style: caption),
                  CompactGroupBy<bool?>(
                    values: const [null, true, false],
                    labelOf: _triLabel,
                    selected: sellableFilter,
                    onChanged: onSellableChanged,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bound', style: caption),
                  CompactGroupBy<bool?>(
                    values: const [null, true, false],
                    labelOf: _triLabel,
                    selected: boundFilter,
                    onChanged: onBoundChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
