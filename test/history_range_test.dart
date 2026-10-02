import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/state/app_state.dart';
import 'package:gw2tp/ui/widgets/day_dial.dart';

import 'test_helpers.dart';

void main() {
  group('HistoryRange', () {
    test('presets keep their labels and windows', () {
      expect(HistoryRange.h1.label, '1H');
      expect(HistoryRange.h1.window, const Duration(hours: 1));
      expect(HistoryRange.h6.window, const Duration(hours: 6));
      expect(HistoryRange.h24.window, const Duration(hours: 24));
      expect(HistoryRange.d3.window, const Duration(days: 3));
      expect(HistoryRange.d7.label, '7D');
    });

    test('days() factory clamps to 1–30 and labels correctly', () {
      expect(HistoryRange.days(1).label, '1D');
      expect(HistoryRange.days(1).window, const Duration(days: 1));
      expect(HistoryRange.days(30).label, '30D');
      expect(HistoryRange.days(0).window, const Duration(days: 1));
      expect(HistoryRange.days(99).window, const Duration(days: 30));
    });

    test('days() normalizes onto the d3/d7 presets', () {
      expect(HistoryRange.days(7), HistoryRange.d7);
      expect(HistoryRange.days(3), HistoryRange.d3);
      expect(identical(HistoryRange.days(7), HistoryRange.d7), isTrue);
    });

    test('dayCount is null for hour presets, set for day ranges', () {
      expect(HistoryRange.h1.dayCount, isNull);
      expect(HistoryRange.h6.dayCount, isNull);
      expect(HistoryRange.h24.dayCount, isNull);
      expect(HistoryRange.d3.dayCount, 3);
      expect(HistoryRange.d7.dayCount, 7);
      expect(HistoryRange.days(21).dayCount, 21);
    });

    test('storageKey round-trips through parse', () {
      for (final r in [
        HistoryRange.h1,
        HistoryRange.h6,
        HistoryRange.h24,
        HistoryRange.d3,
        HistoryRange.d7,
        HistoryRange.days(1),
        HistoryRange.days(14),
        HistoryRange.days(30),
      ]) {
        expect(HistoryRange.parse(r.storageKey), r,
            reason: 'round-trip failed for ${r.label}');
      }
    });

    test('parse keeps old saved preset names working', () {
      expect(HistoryRange.parse('h1'), HistoryRange.h1);
      expect(HistoryRange.parse('h6'), HistoryRange.h6);
      expect(HistoryRange.parse('h24'), HistoryRange.h24);
      expect(HistoryRange.parse('d3'), HistoryRange.d3);
      expect(HistoryRange.parse('d7'), HistoryRange.d7);
    });

    test('parse falls back to 24h on unknown values', () {
      expect(HistoryRange.parse('bogus'), HistoryRange.h24);
      expect(HistoryRange.parse(''), HistoryRange.h24);
    });

    test('equality is by window', () {
      expect(HistoryRange.days(14), HistoryRange.days(14));
      expect(HistoryRange.days(14) == HistoryRange.d7, isFalse);
      expect(HistoryRange.days(14).hashCode,
          HistoryRange.days(14).hashCode);
    });
  });

  group('day dial picker', () {
    /// Pumps a button that opens the dial; returns a getter for the picked
    /// value (null until the sheet pops).
    Future<int? Function()> openDial(
        WidgetTester tester, int initialDays) async {
      int? picked;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showDayDialPicker(context,
                    initialDays: initialDays);
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('day_dial')), findsOneWidget);
      expect(completed, isFalse);
      return () {
        expect(completed, isTrue);
        return picked;
      };
    }

    testWidgets('tap selects a day and pops it', (tester) async {
      final picked = await openDial(tester, 7);
      await tapDialDay(tester, 21);
      expect(picked(), 21);
    });

    testWidgets('dead zone pins to the hard stop instead of wrapping',
        (tester) async {
      // Counterclockwise past 30 (into the gap) stays at 30.
      var picked = await openDial(tester, 15);
      await tapDialAngle(tester, -0.1); // just inside the gap, past 30
      expect(picked(), 30);

      // Clockwise past 1 (into the gap) stays at 1.
      picked = await openDial(tester, 15);
      await tapDialAngle(tester, 0.1); // just inside the gap, past 1
      expect(picked(), 1);
    });

    testWidgets('dismissing the sheet returns null', (tester) async {      var completed = false;
      int? picked = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showDayDialPicker(context, initialDays: 7);
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Tap the scrim to dismiss without choosing (drag-to-dismiss is off
      // so vertical drags belong to the dial).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(picked, isNull);
    });
  });
}
