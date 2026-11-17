import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/ui/screens/item_detail_screen.dart';

import 'fake_gw2_api.dart';
import 'widget_test.dart' show pumpApp;

/// Regression: the Craft card showed 'Item 12156' for Jug of Water
/// instead of its name. Ingredient names come from the meta cache, which
/// sync only warms for owned/traded ids — a vendor-bought ingredient was
/// never seen, so the row fell back to the id label. Opening the detail
/// screen must warm the recipe's ingredient names with its prices.
void main() {
  testWidgets('craft ingredient shows its name, not Item <id>',
      (tester) async {
    final api = FakeGw2Api()
      ..itemDetails = {
        100: {
          'id': 100,
          'name': 'Test Output',
          'description': '',
          'type': 'Trophy',
          'level': 0,
          'rarity': 'Fine',
          'vendor_value': 0,
          'chat_link': '',
          'icon': '',
          'flags': [],
          'restrictions': [],
          'details': {},
        },
      }
      ..quotes = {
        100: const CommerceQuote(
          buyPrice: 1000,
          buyQuantity: 1,
          sellPrice: 1200,
          sellQuantity: 1,
        ),
        12156: const CommerceQuote(
          buyPrice: 100,
          buyQuantity: 5,
          sellPrice: 120,
          sellQuantity: 6,
        ),
      }
      ..recipeIds = {
        100: [1],
      }
      ..recipes = {
        1: const CraftRecipe(
          id: 1,
          type: 'Cooking',
          outputItemId: 100,
          outputCount: 1,
          minRating: 0,
          disciplines: ['Chef'],
          ingredients: [RecipeIngredient(itemId: 12156, count: 1)],
        ),
      }
      ..metaById = {
        12156: const ItemMeta(
          id: 12156,
          name: 'Jug of Water',
          iconUrl: '',
        ),
      };

    // Tall viewport: the detail page is a lazily-built ListView, so a
    // default-height window leaves the Craft card below the fold unbuilt
    // and its finders empty. Render the whole page at once instead.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byIcon(Icons.settings_outlined))).push(
      MaterialPageRoute(builder: (_) => const ItemDetailScreen(itemId: 100)),
    );
    await tester.pumpAndSettle();

    // Flush the meta cache's delayed 2s persist timer (scheduled by the
    // warm this screen triggers) before teardown, or the binding fails
    // the test for a pending timer.
    await tester.pump(const Duration(seconds: 3));

    // Real name, not the id fallback — with the Vendor chip, since the
    // 8c vendor price beats the 100c TP buy.
    expect(find.text('×1 Jug of Water'), findsOneWidget);
    expect(find.text('×1 Item 12156'), findsNothing);
    expect(find.text('Vendor'), findsOneWidget);
  });
}
