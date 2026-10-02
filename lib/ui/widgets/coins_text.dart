/// Coin values rendered with GW2-colored unit suffixes.
///
/// The amount keeps the surrounding text style; only the `g`/`s`/`c`
/// units are tinted gold, silver, and copper. Colors are deepened slightly
/// from the in-game coin hues so they stay legible on light and dark
/// backgrounds.
library;

import 'package:flutter/material.dart';

import '../../util/coins.dart';

/// GW2 coin palette, deepened for text legibility.
const Color coinGold = Color(0xFFB8860B);
const Color coinSilver = Color(0xFF7A8590);
const Color coinCopper = Color(0xFFB5651D);

Color _unitColor(String unit) {
  switch (unit) {
    case 'g':
      return coinGold;
    case 's':
      return coinSilver;
    default:
      return coinCopper;
  }
}

/// Inline spans for a copper value: amounts in [style], units tinted.
/// Handles negative values with a leading minus.
List<InlineSpan> coinSpans(int copper, {TextStyle? style}) {
  final bool negative = copper < 0;
  final spans = <InlineSpan>[];
  if (negative) spans.add(TextSpan(text: '-', style: style));
  final parts = coinParts(copper.abs());
  for (int i = 0; i < parts.length; i++) {
    if (i > 0) spans.add(TextSpan(text: ' ', style: style));
    final p = parts[i];
    spans.add(TextSpan(text: '${p.amount}', style: style));
    spans.add(TextSpan(
      text: p.unit,
      style: (style ?? const TextStyle()).copyWith(color: _unitColor(p.unit)),
    ));
  }
  return spans;
}

/// A coin value like `12g 34s 56c` with GW2-colored unit suffixes.
class CoinsText extends StatelessWidget {
  final int copper;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const CoinsText(
    this.copper, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    return Text.rich(
      TextSpan(children: coinSpans(copper, style: effective)),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
