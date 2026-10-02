import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/ui/widgets/day_dial.dart';

/// Taps the day dial at the tick for [day] (1–30), confirming the choice.
Future<void> tapDialDay(WidgetTester tester, int day) =>
    tapDialAngle(tester, dialAngleForDay(day));

/// Taps the day dial at a raw clockwise-from-top [angle] (radians),
/// confirming the choice.
Future<void> tapDialAngle(WidgetTester tester, double angle) async {
  final dial = find.byKey(const ValueKey('day_dial'));
  expect(dial, findsOneWidget);
  final center = tester.getCenter(dial);
  await tester.tapAt(center + Offset(sin(angle) * 100, -cos(angle) * 100));
  await tester.pumpAndSettle();
}
