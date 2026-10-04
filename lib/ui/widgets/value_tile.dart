/// A labeled coin-value tile: one Card, one column per (label, value) pair.
/// Unifies the Sold/Bought value tiles and the Listings order-value tile.
library;

import 'package:flutter/material.dart';

import 'coins_text.dart';

class ValueTile extends StatelessWidget {
  final List<String> labels;

  /// Copper values, parallel to [labels].
  final List<int> copperValues;

  const ValueTile({
    super.key,
    required this.labels,
    required this.copperValues,
  }) : assert(labels.length == copperValues.length);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(labels[i]),
                    CoinsText(
                      copperValues[i],
                      style: theme.textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
