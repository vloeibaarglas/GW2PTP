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
  });
}
