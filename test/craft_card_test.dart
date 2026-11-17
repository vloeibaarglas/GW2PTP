import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/ui/screens/item_detail_screen.dart';

/// Pumps one stacked ingredient row at phone width.
Future<void> pumpRow(
  WidgetTester tester, {
  required String label,
  int? buy,
  int? sell,
  bool vendorUsed = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: CraftIngredientRow(
            label: label,
            buyLine: buy,
            sellLine: sell,
            vendorUsed: vendorUsed,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CraftIngredientRow (stacked, sketch Option A)', () {
    testWidgets('vendor chip sits right after the item name, same line',
        (tester) async {
      await pumpRow(tester,
          label: '×1 Jug of Water', buy: 8, sell: 8, vendorUsed: true);

      expect(find.text('Vendor'), findsOneWidget);
      final nameRight = tester.getTopRight(find.text('×1 Jug of Water')).dx;
      final chip = tester.getTopLeft(find.text('Vendor'));
      expect(chip.dx, greaterThan(nameRight));
      // Same line: the chip's label sits within the name's line box.
      final nameTop = tester.getTopLeft(find.text('×1 Jug of Water')).dy;
      expect(chip.dy, closeTo(nameTop, 8));
      expect(tester.takeException(), isNull);
    });

    testWidgets('buy and sell share one line', (tester) async {
      await pumpRow(tester,
          label: '×1 Pile of Incandescent Dust', buy: 187, sell: 188);

      final buyTop = tester.getTopLeft(find.text('Buy ')).dy;
      final sellTop = tester.getTopLeft(find.text('Sell ')).dy;
      expect(sellTop, buyTop);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long name wraps without overflow', (tester) async {
      await pumpRow(tester,
          label: '×10 Superior Sigil of Demon Summoning',
          buy: 312,
          sell: 320,
          vendorUsed: true);

      expect(find.text('Vendor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no vendor chip when the vendor price was not used',
        (tester) async {
      await pumpRow(tester, label: '×1 Large Claw', buy: 57, sell: 66);
      expect(find.text('Vendor'), findsNothing);
    });

    testWidgets('vendor chip does not push the pricing line down',
        (tester) async {
      // One vendor row and one plain row side by side: the pricing line
      // must sit the same distance below the row top in both, and the
      // rows must be the same height. (A Chip is at least 32px tall —
      // 30px with compact density — which made the name line on vendor
      // rows taller than the 20px text line and pushed Buy/Sell down.)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: Column(
                children: [
                  CraftIngredientRow(
                    label: '×1 Jug of Water',
                    buyLine: 8,
                    sellLine: 8,
                    vendorUsed: true,
                  ),
                  CraftIngredientRow(
                    label: '×1 Large Claw',
                    buyLine: 57,
                    sellLine: 66,
                    vendorUsed: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rows = find.byType(CraftIngredientRow);
      expect(tester.getSize(rows.first).height,
          tester.getSize(rows.last).height);
      final firstBuyDy = tester.getTopLeft(find.text('Buy ').first).dy;
      final firstTop = tester.getTopLeft(rows.first).dy;
      final lastBuyDy = tester.getTopLeft(find.text('Buy ').last).dy;
      final lastTop = tester.getTopLeft(rows.last).dy;
      expect(firstBuyDy - firstTop, lastBuyDy - lastTop);
      expect(tester.takeException(), isNull);
    });
  });
}
