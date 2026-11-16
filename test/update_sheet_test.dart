import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/state/app_update_state.dart';
import 'package:gw2tp/ui/widgets/update_button.dart';
import 'package:gw2tp/ui/widgets/update_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_check_test.dart' show releaseJson;

Future<AppUpdateState> stateWith(MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return AppUpdateState(
    prefs: prefs,
    client: client,
    loadCurrentVersion: () async => '0.1.0',
  );
}

Future<void> pumpSheet(WidgetTester tester, AppUpdateState state) async {
  await state.init();
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider.value(
        value: state,
        child: const Scaffold(body: UpdateSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateSheet', () {
    testWidgets('idle shows Check, then an available update offers Install',
        (tester) async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final state = await stateWith(client);
      await pumpSheet(tester, state);

      expect(find.text('App updates'), findsOneWidget);
      expect(find.text('Version 0.1.0'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Auto-check for updates'), findsOneWidget);
      expect(find.text('Install update'), findsNothing);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('Version 0.1.1 is available'), findsOneWidget);
      expect(find.text('Install update'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
    });

    testWidgets('up-to-date check says so', (tester) async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(releaseJson(tag: 'v0.1.0')), 200));
      final state = await stateWith(client);
      await pumpSheet(tester, state);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text("You're up to date."), findsOneWidget);
    });

    testWidgets('failed check shows the error and Try again',
        (tester) async {
      final client = MockClient((_) async => http.Response('no', 500));
      final state = await stateWith(client);
      await pumpSheet(tester, state);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.textContaining('GitHub returned 500'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('auto-check toggle flips and persists', (tester) async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final state = await stateWith(client);
      await pumpSheet(tester, state);

      final toggle = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        find.text('Only checks when you tap Check for updates.'),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        find.text('Checks every 3 days when you open the app.'),
        findsOneWidget,
      );
      expect(state.settings.autoCheck, isTrue);
    });

    testWidgets('Later hides the update offer until the next check',
        (tester) async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final state = await stateWith(client);
      await pumpSheet(tester, state);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Install update'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(state.updateAvailable, isFalse);
    });
  });

  group('UpdateButton', () {
    testWidgets('dot appears only when an update is available',
        (tester) async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(releaseJson()), 200));
      final state = await stateWith(client);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: state,
            child: Scaffold(
              appBar: AppBar(actions: [UpdateButton()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
        isFalse,
      );

      await state.check();
      await tester.pumpAndSettle();

      expect(
        tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
        isTrue,
      );
    });
  });
}
