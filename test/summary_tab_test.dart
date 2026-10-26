import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/models.dart';

import 'fake_gw2_api.dart';
import 'widget_test.dart' show pumpApp;

void main() {
  testWidgets('Summary tab shows cross-section highlights and jumps',
      (tester) async {
    final api = FakeGw2Api(
      historySells: [
        {
          'id': 1,
          'item_id': 19684,
          'price': 150,
          'quantity': 2,
          'purchased': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        },
      ],
      delivery: DeliveryBox(
        coins: 500,
        items: [
          const InventoryEntry(
              itemId: 100, count: 3, location: 'Delivery box'),
        ],
      ),
    );
    await pumpApp(tester, apiKey: 'test-key', api: api);
    await tester.pumpAndSettle();

    // Summary is the default bottom tab: highlights from every section.
    expect(find.text('Listed value'), findsOneWidget);
    expect(find.text('Net value'), findsOneWidget);
    expect(find.text('Open orders'), findsOneWidget);
    expect(find.text('To pick up'), findsOneWidget);
    expect(find.text('Sold · 24h'), findsOneWidget);
    expect(find.text('Sold · 7d'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);

    // Recent fills sit below the tiles: scroll the ListView to build them.
    await tester.scrollUntilVisible(find.text('Recent fills'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Recent fills'), findsOneWidget);
    expect(find.text('Item 19684'), findsOneWidget);

    // Tapping a tile jumps to the bottom tab it summarizes.
    await tester.scrollUntilVisible(find.text('Sold · 24h'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sold · 24h'));
    await tester.pumpAndSettle();
    expect(find.text('Sold Value'), findsOneWidget);
  });
}
