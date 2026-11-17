import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_gw2_api.dart';
import 'widget_test.dart' show pumpApp;

void main() {
  testWidgets('App Updates lives in Settings, not on an app bar',
      (tester) async {
    // Tall viewport: the settings page is a lazily-built ListView, so a
    // default-height window leaves lower sections unbuilt and their
    // finders empty. Render the whole page at once instead.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpApp(tester, apiKey: 'test-key', api: FakeGw2Api());
    await tester.pumpAndSettle();

    // No update button anywhere on the home screen.
    expect(find.byIcon(Icons.system_update_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // The section is there, with the manual check and the auto-check
    // toggle; nothing was checked yet.
    expect(find.text('APP UPDATES'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Auto-check for updates'), findsOneWidget);
    expect(find.text('Never checked'), findsOneWidget);
    expect(
      find.text('Only checks when you tap Check for updates.'),
      findsOneWidget,
    );

    // Flipping the toggle persists and rewords its own subtitle.
    await tester.tap(find.text('Auto-check for updates'));
    await tester.pumpAndSettle();
    expect(
      find.text('Checks every 3 days when you open the app.'),
      findsOneWidget,
    );
  });
}
