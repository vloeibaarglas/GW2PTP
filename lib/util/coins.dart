/// Copper-to-coins formatting for Guild Wars 2 money values.
///
/// GW2 money is an integer number of copper: 1 gold = 10,000 copper,
/// 1 silver = 100 copper.
library;

/// Formats [copper] as e.g. `12g 34s 56c`. Zero parts are omitted except
/// that a zero value renders as `0c`.
String formatCoins(int copper) {
  final bool negative = copper < 0;
  final parts = coinParts(copper.abs());
  final text = parts.map((p) => '${p.amount}${p.unit}').join(' ');
  return negative ? '-$text' : text;
}

/// Breaks [copper] into (amount, unit) pairs for rich rendering, e.g.
/// `[(12, 'g'), (34, 's')]`. Zero parts are omitted except that a zero
/// value yields `[(0, 'c')]`. The input must be non-negative.
List<({int amount, String unit})> coinParts(int copper) {
  assert(copper >= 0, 'coinParts takes a non-negative value');
  int rest = copper;
  final int gold = rest ~/ 10000;
  rest %= 10000;
  final int silver = rest ~/ 100;
  final int bronze = rest % 100;

  final parts = <({int amount, String unit})>[];
  if (gold > 0) parts.add((amount: gold, unit: 'g'));
  if (silver > 0) parts.add((amount: silver, unit: 's'));
  if (bronze > 0 || parts.isEmpty) parts.add((amount: bronze, unit: 'c'));
  return parts;
}

/// Net proceeds of a sell listing after the 15% Trading Post cut
/// (10% listing fee + 5% exchange fee), rounded down like the game does.
int netOfFees(int grossCopper) => (grossCopper * 85) ~/ 100;

/// Masks an API key for display: the raw key is never shown anywhere in
/// the UI. Returns `'********'` when a key is set, `''` when not.
String maskApiKey(String? key) => (key == null || key.isEmpty) ? '' : '********';
