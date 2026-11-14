/// Buy/sell pricing for one craft recipe (pure math, no widgets).
///
/// The Craft card shows both price bases side by side: Buy = buy-order
/// prices (place bids, wait, cheaper), Sell = ask prices (instant buy).
/// Per ingredient, the effective price is the cheaper of the Trading Post
/// basis price and the vendor price (vendor stock is unlimited, so it caps
/// both columns). An ingredient with no TP quote but a vendor price uses
/// the vendor price for both columns — that is the Jug of Water fix
/// (a vendor item whose TP price is wrong/missing). With neither, the
/// basis is unpriced, as before.
///
/// A 0 side means "no orders on that side", not a price: it must never
/// price an ingredient at 0.
library;

import '../api/models.dart';
import '../store/vendor_prices.dart';

/// One ingredient line of the Craft card.
class CraftIngredientLine {
  final RecipeIngredient ingredient;

  /// Total copper at buy-order basis (bid x count), null = unpriced.
  final int? buyLine;

  /// Total copper at instant-buy basis (ask x count), null = unpriced.
  final int? sellLine;

  /// The vendor price was the cheapest price for the Buy column.
  final bool vendorUsedBuy;

  /// The vendor price was the cheapest price for the Sell column.
  final bool vendorUsedSell;

  const CraftIngredientLine({
    required this.ingredient,
    required this.buyLine,
    required this.sellLine,
    required this.vendorUsedBuy,
    required this.vendorUsedSell,
  });

  /// The vendor price was used for at least one column.
  bool get vendorUsed => vendorUsedBuy || vendorUsedSell;
}

/// Both price bases for one recipe, computed by [CraftPricing.compute].
class CraftPricing {
  /// Per-ingredient lines, in recipe order.
  final List<CraftIngredientLine> lines;

  /// The crafted item's own best bid, null when unlisted / no bids.
  final int? itemBuy;

  /// The crafted item's own best ask, null when unlisted / no asks.
  final int? itemSell;

  /// Ingredient cost at buy-order basis; null unless every ingredient
  /// has a Buy price.
  final int? costBuy;

  /// Ingredient cost at instant-buy basis; null unless every ingredient
  /// has a Sell price.
  final int? costSell;

  /// Output net of 15% fees at the bid (instant-sell into buy orders),
  /// null when there is no bid.
  final int? netBuy;

  /// Output net of 15% fees at the ask (list-sell), null when no ask.
  final int? netSell;

  /// Column-consistent margin: [netBuy] - [costBuy].
  final int? marginBuy;

  /// Column-consistent margin: [netSell] - [costSell].
  final int? marginSell;

  /// [marginBuy] / [costBuy], null when the cost is 0 or absent.
  final double? roiBuy;

  /// [marginSell] / [costSell], null when the cost is 0 or absent.
  final double? roiSell;

  const CraftPricing({
    required this.lines,
    required this.itemBuy,
    required this.itemSell,
    required this.costBuy,
    required this.costSell,
    required this.netBuy,
    required this.netSell,
    required this.marginBuy,
    required this.marginSell,
    required this.roiBuy,
    required this.roiSell,
  });

  static CraftPricing compute({
    required CraftRecipe recipe,
    required CommerceQuote? quote,
    required Map<int, CommerceQuote> ingredientPrices,
    Map<int, int> vendorPrices = kVendorPrices,
  }) {
    final lines = <CraftIngredientLine>[];
    for (final ing in recipe.ingredients) {
      final q = ingredientPrices[ing.itemId];
      final vendor = vendorPrices[ing.itemId];
      final buyUnit = _effectiveSide(q?.buyPrice, vendor);
      final sellUnit = _effectiveSide(q?.sellPrice, vendor);
      lines.add(
        CraftIngredientLine(
          ingredient: ing,
          buyLine: buyUnit == null ? null : buyUnit * ing.count,
          sellLine: sellUnit == null ? null : sellUnit * ing.count,
          vendorUsedBuy: vendor != null && buyUnit == vendor,
          vendorUsedSell: vendor != null && sellUnit == vendor,
        ),
      );
    }

    int? sum(Iterable<int?> values) {
      var total = 0;
      for (final v in values) {
        if (v == null) return null;
        total += v;
      }
      return total;
    }

    final costBuy = sum(lines.map((l) => l.buyLine));
    final costSell = sum(lines.map((l) => l.sellLine));

    int? net(int? sidePrice) {
      if (sidePrice == null || sidePrice <= 0) return null;
      return (sidePrice * recipe.outputCount * 0.85).round();
    }

    final netBuy = net(quote?.buyPrice);
    final netSell = net(quote?.sellPrice);

    // Column-consistent pairing: Margin Buy pairs the Buy exit
    // (instant-sell into buy orders) with the Buy entry (buy-order
    // ingredient cost), and Margin Sell pairs the Sell exit (list-sell)
    // with the Sell entry (instant-buy ingredient cost). This is NOT a
    // best/worst cross-pairing (cheapest entry with best exit) — each
    // column prices one coherent execution path.
    final marginBuy =
        (netBuy != null && costBuy != null) ? netBuy - costBuy : null;
    final marginSell =
        (netSell != null && costSell != null) ? netSell - costSell : null;

    double? roi(int? margin, int? cost) {
      if (margin == null || cost == null || cost <= 0) return null;
      return margin / cost;
    }

    return CraftPricing(
      lines: lines,
      itemBuy: (quote != null && quote.buyPrice > 0) ? quote.buyPrice : null,
      itemSell: (quote != null && quote.sellPrice > 0) ? quote.sellPrice : null,
      costBuy: costBuy,
      costSell: costSell,
      netBuy: netBuy,
      netSell: netSell,
      marginBuy: marginBuy,
      marginSell: marginSell,
      roiBuy: roi(marginBuy, costBuy),
      roiSell: roi(marginSell, costSell),
    );
  }

  /// Effective per-unit price for one basis: the cheaper of the TP side
  /// price and the vendor price. A 0 TP side means "no orders on that
  /// side" and counts as absent; with no TP side and no vendor price the
  /// basis is unpriced (null).
  static int? _effectiveSide(int? tpSide, int? vendor) {
    final tp = (tpSide != null && tpSide > 0) ? tpSide : null;
    if (tp == null) return vendor;
    if (vendor == null) return tp;
    return tp < vendor ? tp : vendor;
  }
}
