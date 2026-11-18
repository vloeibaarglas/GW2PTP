import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';
import 'package:gw2tp/ui/screens/item_detail_screen.dart';

import 'fake_gw2_api.dart';
import 'widget_test.dart' show pumpApp;

/// Detail-screen redesign (2026-11-17): the Craft card prices all four
/// entry x exit scenarios in a tappable grid, and the position card
/// shows the units listed ahead of each open sell plus the last fill's
/// relative age.
void main() {
  const itemId = 100;

  Map<String, dynamic> itemDetailJson() => {
        'id': itemId,
        'name': 'Test Potion',
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
      };

  /// 8868-shaped numbers: cost 297c at bid / 304c at ask, net 314c at
  /// bid / 349c at ask (output x3), so the four scenarios are
  /// 17c/5.7%, 52c/17.5%, 10c/3.3%, 45c/14.8%.
  FakeGw2Api craftApi() {
    return FakeGw2Api()
      ..itemDetails = {itemId: itemDetailJson()}
      ..quotes = {
        itemId: const CommerceQuote(
          buyPrice: 123,
          buyQuantity: 10,
          sellPrice: 137,
          sellQuantity: 10,
        ),
        24276: const CommerceQuote(
          buyPrice: 197,
          buyQuantity: 5,
          sellPrice: 199,
          sellQuantity: 6,
        ),
        24350: const CommerceQuote(
          buyPrice: 59,
          buyQuantity: 5,
          sellPrice: 63,
          sellQuantity: 6,
        ),
        24299: const CommerceQuote(
          buyPrice: 33,
          buyQuantity: 5,
          sellPrice: 34,
          sellQuantity: 6,
        ),
      }
      ..recipeIds = {
        itemId: [1],
      }
      ..recipes = {
        1: const CraftRecipe(
          id: 1,
          type: 'Cooking',
          outputItemId: itemId,
          outputCount: 3,
          minRating: 0,
          disciplines: ['Artificer'],
          ingredients: [
            RecipeIngredient(itemId: 24276, count: 1),
            RecipeIngredient(itemId: 24350, count: 1),
            RecipeIngredient(itemId: 24299, count: 1),
            RecipeIngredient(itemId: 12156, count: 1),
          ],
        ),
      }
      ..metaById = {
        24276: const ItemMeta(
          id: 24276,
          name: 'Pile of Incandescent Dust',
          iconUrl: '',
        ),
        24350: const ItemMeta(
          id: 24350,
          name: 'Large Claw',
          iconUrl: '',
        ),
        24299: const ItemMeta(
          id: 24299,
          name: 'Intricate Totem',
          iconUrl: '',
        ),
        12156: const ItemMeta(
          id: 12156,
          name: 'Jug of Water',
          iconUrl: '',
        ),
      };
  }

  Future<void> pumpDetail(WidgetTester tester, FakeGw2Api api) async {
    // Tall viewport: the detail page is a lazily-built ListView, so a
    // default-height window leaves the lower cards unbuilt.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byIcon(Icons.settings_outlined))).push(
      MaterialPageRoute(
          builder: (_) => const ItemDetailScreen(itemId: itemId)),
    );
    await tester.pumpAndSettle();

    // Flush the meta cache's delayed 2s persist timer (scheduled by the
    // warm this screen triggers) before teardown, or the binding fails
    // the test for a pending timer.
    await tester.pump(const Duration(seconds: 3));
  }

  group('scenario grid', () {
    testWidgets('defaults to the usual route and taps update the breakdown',
        (tester) async {
      await pumpDetail(tester, craftApi());

      // Best craft strip leads with the usual route.
      expect(find.text('Best craft'), findsOneWidget);
      expect(find.text('Your usual'), findsOneWidget);

      // Default selection is bid entry / ask exit.
      expect(
        find.text(
            'cost 2s 97c → net sell 3s 49c → margin 52c · ROI 17.5%'),
        findsOneWidget,
      );

      // Tapping the ask-entry / bid-exit cell (margin 10c) re-points
      // the breakdown strip at that scenario.
      await tester.tap(find.text('10c'));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'cost 3s 4c → net sell 3s 14c → margin 10c · ROI 3.3%'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('context rows show cost and net at both bases',
        (tester) async {
      await pumpDetail(tester, craftApi());

      expect(find.text('Craft cost'), findsOneWidget);
      expect(find.text('Sells for (net)'), findsOneWidget);
      expect(find.text('Craft margin & ROI — all 4 scenarios'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('position card', () {
    testWidgets('open sells show units ahead and last fill shows its age',
        (tester) async {
      final api = craftApi()
        ..sells = const [
          TpOrder(id: 1, itemId: itemId, price: 141, quantity: 11593),
          TpOrder(id: 2, itemId: itemId, price: 143, quantity: 2231),
        ]
        ..books = {
          itemId: const ListingBook(
            bids: [
              ListingLevel(unitPrice: 123, quantity: 100, listings: 1),
            ],
            asks: [
              ListingLevel(unitPrice: 130, quantity: 1000, listings: 1),
              ListingLevel(unitPrice: 135, quantity: 2000, listings: 1),
              ListingLevel(unitPrice: 140, quantity: 3000, listings: 1),
              ListingLevel(unitPrice: 141, quantity: 5000, listings: 1),
              ListingLevel(unitPrice: 142, quantity: 7000, listings: 1),
            ],
          ),
        }
        ..historySells = [
          {
            'id': 1,
            'item_id': itemId,
            'price': 141,
            'quantity': 250,
            'purchased': DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 9, minutes: 30))
                .toIso8601String(),
            'created': DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 9, minutes: 30))
                .toIso8601String(),
          },
        ];

      await pumpDetail(tester, api);

      // One grouped header, not an "Open sell" label per row.
      expect(find.text('Open sells'), findsOneWidget);
      expect(find.text('2 listings · 13824 units'), findsOneWidget);
      expect(find.text('Open sell'), findsNothing);

      // Ahead counts are asks strictly below the price (same-price
      // excluded): 141 -> 1000+2000+3000, 143 -> +5000+7000.
      expect(find.text(' (6000 ahead)'), findsOneWidget);
      expect(find.text(' (18000 ahead)'), findsOneWidget);

      // Last fill carries its relative age — in the position card and
      // in the Best craft strip's position line.
      expect(find.text('Last fill'), findsOneWidget);
      expect(find.textContaining('9 Hr Ago'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
