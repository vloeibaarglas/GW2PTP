import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/store/vendor_prices.dart';
import 'package:gw2tp/util/craft_pricing.dart';

CraftRecipe recipe({
  List<RecipeIngredient> ingredients = const [],
  int outputCount = 1,
}) =>
    CraftRecipe(
      id: 1,
      type: 'Test',
      outputItemId: 999,
      outputCount: outputCount,
      minRating: 0,
      disciplines: const ['Chef'],
      ingredients: ingredients,
    );

CommerceQuote quote({required int buy, required int sell}) => CommerceQuote(
      buyPrice: buy,
      buyQuantity: 10,
      sellPrice: sell,
      sellQuantity: 10,
    );

void main() {
  group('CraftPricing', () {
    test('buy and sell columns from TP quotes, column-consistent margins', () {
      final pricing = CraftPricing.compute(
        recipe: recipe(
          ingredients: const [
            RecipeIngredient(itemId: 100, count: 2),
            RecipeIngredient(itemId: 101, count: 3),
          ],
          outputCount: 1,
        ),
        quote: quote(buy: 120, sell: 200),
        ingredientPrices: {
          100: quote(buy: 10, sell: 15),
          101: quote(buy: 20, sell: 30),
        },
        vendorPrices: const {},
      );

      expect(pricing.costBuy, 2 * 10 + 3 * 20); // 80
      expect(pricing.costSell, 2 * 15 + 3 * 30); // 120
      expect(pricing.netBuy, (120 * 0.85).round()); // 102
      expect(pricing.netSell, (200 * 0.85).round()); // 170
      // Column-consistent: Buy exit with Buy entry, Sell exit with Sell entry.
      expect(pricing.marginBuy, 102 - 80); // 22, NOT 170 - 80 (best case)
      expect(pricing.marginSell, 170 - 120); // 50, NOT 102 - 120 (worst case)
      expect(pricing.roiBuy, closeTo(22 / 80, 1e-9));
      expect(pricing.roiSell, closeTo(50 / 120, 1e-9));
      expect(pricing.itemBuy, 120);
      expect(pricing.itemSell, 200);
      expect(pricing.lines.every((l) => !l.vendorUsed), isTrue);
    });

    test('vendor price caps both columns and marks the line', () {
      final pricing = CraftPricing.compute(
        recipe: recipe(
          ingredients: const [RecipeIngredient(itemId: 200, count: 5)],
        ),
        quote: quote(buy: 100, sell: 150),
        ingredientPrices: {
          // Bid below vendor, ask above vendor: vendor wins only the Sell column.
          200: quote(buy: 10, sell: 40),
        },
        vendorPrices: const {200: 25},
      );

      final line = pricing.lines.single;
      expect(line.buyLine, 5 * 10); // bid is cheaper than vendor
      expect(line.sellLine, 5 * 25); // vendor caps the ask
      expect(line.vendorUsedBuy, isFalse);
      expect(line.vendorUsedSell, isTrue);
      expect(line.vendorUsed, isTrue);
      expect(pricing.costBuy, 50);
      expect(pricing.costSell, 125);
    });

    test('no TP quote + vendor price uses vendor for both columns', () {
      // Jug of Water (12156) is a vendor item: 8c from a merchant, and its
      // TP price is wrong/missing — no quote at all.
      final pricing = CraftPricing.compute(
        recipe: recipe(
          ingredients: const [RecipeIngredient(itemId: 12156, count: 10)],
        ),
        quote: quote(buy: 100, sell: 150),
        ingredientPrices: const {},
      );

      expect(kVendorPrices[12156], 8);
      final line = pricing.lines.single;
      expect(line.buyLine, 10 * 8);
      expect(line.sellLine, 10 * 8);
      expect(line.vendorUsed, isTrue);
      expect(pricing.costBuy, 80);
      expect(pricing.costSell, 80);
    });

    test('a 0 side means no orders, not a price', () {
      final pricing = CraftPricing.compute(
        recipe: recipe(
          ingredients: const [RecipeIngredient(itemId: 300, count: 2)],
        ),
        quote: quote(buy: 0, sell: 150),
        ingredientPrices: {
          // Asks exist, no bids: the Buy column is unpriced, not free.
          300: quote(buy: 0, sell: 40),
        },
        vendorPrices: const {},
      );

      expect(pricing.lines.single.buyLine, isNull);
      expect(pricing.lines.single.sellLine, 2 * 40);
      expect(pricing.costBuy, isNull);
      expect(pricing.costSell, 80);
      expect(pricing.netBuy, isNull);
      expect(pricing.netSell, (150 * 0.85).round());
      expect(pricing.marginBuy, isNull);
      expect(pricing.marginSell, (150 * 0.85).round() - 80);
      expect(pricing.roiBuy, isNull);
      expect(pricing.itemBuy, isNull);
      expect(pricing.itemSell, 150);
    });

    test('neither TP nor vendor keeps the ingredient unpriced', () {
      final pricing = CraftPricing.compute(
        recipe: recipe(
          ingredients: const [RecipeIngredient(itemId: 400, count: 1)],
        ),
        quote: quote(buy: 100, sell: 150),
        ingredientPrices: const {},
        vendorPrices: const {},
      );

      expect(pricing.lines.single.buyLine, isNull);
      expect(pricing.lines.single.sellLine, isNull);
      expect(pricing.costBuy, isNull);
      expect(pricing.costSell, isNull);
      expect(pricing.marginBuy, isNull);
      expect(pricing.marginSell, isNull);
      expect(pricing.roiBuy, isNull);
      expect(pricing.roiSell, isNull);
    });

    test('zero-cost recipe shows an em dash ROI (no divide by zero)', () {
      final pricing = CraftPricing.compute(
        recipe: recipe(ingredients: const []),
        quote: quote(buy: 100, sell: 150),
        ingredientPrices: const {},
        vendorPrices: const {},
      );

      expect(pricing.costBuy, 0);
      expect(pricing.costSell, 0);
      expect(pricing.marginBuy, (100 * 0.85).round());
      expect(pricing.roiBuy, isNull);
      expect(pricing.roiSell, isNull);
    });

    test('vendor tie counts as vendor-used', () {
      final pricing = CraftPricing.compute(
        recipe: recipe(
          ingredients: const [RecipeIngredient(itemId: 500, count: 1)],
        ),
        quote: quote(buy: 100, sell: 150),
        ingredientPrices: {500: quote(buy: 25, sell: 25)},
        vendorPrices: const {500: 25},
      );

      expect(pricing.lines.single.vendorUsed, isTrue);
      expect(pricing.lines.single.buyLine, 25);
      expect(pricing.lines.single.sellLine, 25);
    });
  });
}
