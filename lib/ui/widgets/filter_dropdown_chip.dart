/// Dropdown filter chips for the compact filter bars on the history and
/// listings tabs: one row of tonal chips (icon + current value + chevron),
/// each opening a bottom sheet with radio options and a one-line
/// explanation per option.
library;

import 'package:flutter/material.dart';

/// One selectable option in a [FilterDropdownChip]'s sheet.
class FilterOption<T> {
  final T value;
  final String label;
  final String? description;

  const FilterOption({
    required this.value,
    required this.label,
    this.description,
  });
}

/// The tonal chip visuals, shared by [FilterDropdownChip] and bespoke
/// chips (like the time-window chip) that need a custom sheet.
class FilterChipShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const FilterChipShell({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                    color: fg,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [FilterChipShell] that opens a bottom sheet listing [options] as
/// radio rows; picking one pops the sheet and calls [onChanged].
class FilterDropdownChip<T> extends StatelessWidget {
  final IconData icon;
  final String currentLabel;
  final String sheetTitle;
  final List<FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const FilterDropdownChip({
    super.key,
    required this.icon,
    required this.currentLabel,
    required this.sheetTitle,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChipShell(
      icon: icon,
      label: currentLabel,
      onTap: () => _openSheet(context),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                sheetTitle,
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  RadioGroup<T>(
                    groupValue: selected,
                    onChanged: (v) {
                      if (v != null) Navigator.of(sheetContext).pop(v);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final o in options)
                          RadioListTile<T>(
                            value: o.value,
                            title: Text(o.label),
                            subtitle: o.description == null
                                ? null
                                : Text(o.description!),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }
}
