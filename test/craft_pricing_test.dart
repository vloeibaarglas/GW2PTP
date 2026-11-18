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
    test('buy and sell columns from TP quotes, four scenarios', () {
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
      // Every entry x exit pair is priced: the patient path (bid
      // entry, ask exit) is the best one, not the column pairing.
      CraftScenario s(CraftBasis e, CraftBasis x) =>
          pricing.scenario(e, x);
      expect(s(CraftBasis.bid, CraftBasis.bid).margin, 102 - 80); // 22
      expect(s(CraftBasis.bid, CraftBasis.bid).roi, closeTo(22 / 80, 1e-9));
      expect(s(CraftBasis.bid, CraftBasis.ask).margin, 170 - 80); // 90
      expect(s(CraftBasis.bid, CraftBasis.ask).roi, closeTo(90 / 80, 1e-9));
      expect(s(CraftBasis.ask, CraftBasis.bid).margin, 102 - 120); // -18
      expect(
          s(CraftBasis.ask, CraftBasis.bid).roi, closeTo(-18 / 120, 1e-9));
      expect(s(CraftBasis.ask, CraftBasis.ask).margin, 170 - 120); // 50
      expect(s(CraftBasis.ask, CraftBasis.ask).roi, closeTo(50 / 120, 1e-9));
      expect(s(CraftBasis.bid, CraftBasis.ask).isUsual, isTrue);
      expect(s(CraftBasis.bid, CraftBasis.bid).isUsual, isFalse);
      final best = pricing.best;
      expect(best, isNotNull);
      expect(best!.entry, CraftBasis.bid);
      expect(best.exit, CraftBasis.ask);
      expect(best.margin, 90);
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
      // Only the ask-entry / ask-exit cell is priced.
      CraftScenario s(CraftBasis e, CraftBasis x) =>
          pricing.scenario(e, x);
      expect(s(CraftBasis.bid, CraftBasis.bid).margin, isNull);
      expect(s(CraftBasis.bid, CraftBasis.ask).margin, isNull);
      expect(s(CraftBasis.ask, CraftBasis.bid).margin, isNull);
      expect(s(CraftBasis.ask, CraftBasis.ask).margin,
          (150 * 0.85).round() - 80);
      expect(s(CraftBasis.ask, CraftBasis.ask).roi,
          closeTo(((150 * 0.85).round() - 80) / 80, 1e-9));
      final best = pricing.best;
      expect(best, isNotNull);
      expect(best!.entry, CraftBasis.ask);
      expect(best.exit, CraftBasis.ask);
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
      expect(pricing.scenarios.every((s) => s.margin == null), isTrue);
      expect(pricing.scenarios.every((s) => s.roi == null), isTrue);
      expect(pricing.best, isNull);
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
      // Margins are priced (free ingredients), ROIs are null.
      expect(
        pricing.scenario(CraftBasis.bid, CraftBasis.bid).margin,
        (100 * 0.85).round(),
      );
      expect(pricing.scenarios.every((s) => s.roi == null), isTrue);
      expect(pricing.best, isNotNull);
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
