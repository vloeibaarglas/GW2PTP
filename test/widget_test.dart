import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/gw2_client.dart';
import 'package:gw2tp/main.dart';
import 'package:gw2tp/store/key_store.dart';
import 'package:gw2tp/sync/background_sync.dart';
import 'package:gw2tp/sync/fill_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gw2_api.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  String? apiKey,
  Gw2Api? api,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    TpConsoleApp(
      prefs: prefs,
      api: api ?? FakeGw2Api(),
      keys: FakeKeyStore(apiKey),
      notifier: FakeFillNotifier(),
      syncService: FakeSyncService(),
    ),
  );
}

void main() {
  testWidgets('boots to the key gate when no API key is stored',
      (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    // First-run settings gate, not a crash or a blank spinner.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.textContaining('Guild Wars 2 API key to get started'),
        findsOneWidget);
    expect(find.text('Status: Not Set'), findsOneWidget);
    // The key is never displayed.
    expect(find.text('Status: ******** (Set)'), findsNothing);
  });

  testWidgets('boots to the home screen when an API key is stored',
      (tester) async {
    await pumpApp(tester, apiKey: 'test-key');
    await tester.pumpAndSettle();

    expect(find.text('Holdings'), findsOneWidget);
    // 'Listings' is both the app-bar title (first tab) and a nav label.
    expect(find.text('Listings'), findsWidgets);
    expect(find.text('Deliveries'), findsOneWidget);
    // Bottom navigation is present.
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('settings masks a stored key', (tester) async {
    await pumpApp(tester, apiKey: 'SECRET-KEY-1234');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Status: ******** (Set)'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
  });

  testWidgets('missing key permissions show a warning banner', (tester) async {
    final api = FakeGw2Api(grantedPermissions: const ['account']);
    await pumpApp(tester, apiKey: 'limited-key', api: api);
    await tester.pumpAndSettle();

    // The banner names the missing permissions…
    expect(find.textContaining('API key is missing:'), findsOneWidget);
    expect(find.textContaining('Trading Post'), findsWidgets);
    // …and the sync still completes for the sections the key allows.
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });
}
