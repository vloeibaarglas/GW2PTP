import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_gw2_api.dart';
import 'widget_test.dart' show pumpApp;

void main() {
  testWidgets('settings uses the v3 grouping', (tester) async {
    // Tall viewport: the settings page is a lazily-built ListView, so a
    // default-height window leaves lower sections unbuilt and their
    // finders empty. Render the whole page at once instead.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpApp(tester, apiKey: 'test-key', api: FakeGw2Api());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // v3 sections.
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Cached Data'), findsOneWidget);
    // Old section titles are gone.
    expect(find.text('API Key'), findsNothing);
    expect(find.text('API Permissions'), findsNothing);
    expect(find.text('Sync Mode'), findsNothing);
    expect(find.text('Manual Refresh'), findsNothing);
    expect(find.text('Theme'), findsNothing);
    // Cooldown lives in Sync and renders in passive mode too, while the
    // active-only interval slider stays hidden.
    expect(find.text('Refresh Cooldown'), findsOneWidget);
    expect(find.text('Check Interval'), findsNothing);
    // Fixed permissions copy.
    expect(
        find.text('These permissions are needed for full data.'),
        findsOneWidget);
  });
}
