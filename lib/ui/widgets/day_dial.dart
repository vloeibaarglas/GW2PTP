/// Rotary day-range dial: a smartwatch-crown style picker for 1–30 days.
///
/// Drag around the dial (or tap a position) to turn it; each day detent
/// fires a haptic tick. Releasing the finger confirms the selection and
/// pops it back to the caller. Dragging the sheet down dismisses without
/// changing anything.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Haptics are best-effort: widget tests (and some devices) have no
/// platform channel for them, and a dial must never crash on feedback.
Future<void> _haptic(Future<void> Function() call) async {
  try {
    await call();
  } catch (_) {}
}

/// Dial geometry: 30 detents spread clockwise over a 312° arc starting
/// just clockwise of the top. The 48° dead zone at the top holds the
/// stopper — the scale does not wrap, it hits a hard stop at 30 (and 1).
const int dialDetents = 30;

/// Half the dead-zone gap at the top of the dial, in radians.
const double dialGapHalf = 24 * pi / 180;

/// Clockwise sweep covered by the detents, in radians.
const double dialSweep = 2 * pi - dialGapHalf * 2;

/// Clockwise-from-top angle (radians) of a day's tick.
double dialAngleForDay(int day) =>
    dialGapHalf + (day.clamp(1, dialDetents) - 1) / (dialDetents - 1) * dialSweep;

/// Opens the dial in a bottom sheet. Returns the chosen day count, or null
/// when dismissed.
///
/// The sheet is scroll-controlled (no 9/16 height cap — the dial plus
/// labels need ~430dp) and drag-to-dismiss is off: vertical drags belong to
/// the dial, and the sheet would otherwise steal them. Tapping the scrim
/// or the system back button still dismisses.
Future<int?> showDayDialPicker(BuildContext context,
    {required int initialDays}) {
  _haptic(HapticFeedback.lightImpact);
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    enableDrag: false,
    builder: (_) => _DayDialSheet(initialDays: initialDays.clamp(1, 30)),
  );
}

class _DayDialSheet extends StatefulWidget {
  final int initialDays;

  const _DayDialSheet({required this.initialDays});

  @override
  State<_DayDialSheet> createState() => _DayDialSheetState();
}

class _DayDialSheetState extends State<_DayDialSheet> {
  late int _days;

  @override
  void initState() {
    super.initState();
    _days = widget.initialDays;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Range', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Turn the dial to choose 1–30 days.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _DayDial(
              days: _days,
              onChanged: (d) => setState(() => _days = d),
              onReleased: () => Navigator.of(context).pop(_days),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDial extends StatefulWidget {
  final int days;
  final ValueChanged<int> onChanged;
  final VoidCallback onReleased;

  const _DayDial({
    required this.days,
    required this.onChanged,
    required this.onReleased,
  });

  @override
  State<_DayDial> createState() => _DayDialState();
}

class _DayDialState extends State<_DayDial> {
  /// True while the finger is pressed into the dead zone past an end —
  /// the stopper thud fires once per entry, not continuously.
  bool _atStop = false;

  /// Maps a pointer position to a day. The angle is clockwise from the
  /// top; positions in the dead-zone gap pin to the nearest end (the hard
  /// stop) instead of wrapping around to the other side.
  void _handle(Offset local, Size size) {
    final center = size.center(Offset.zero);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    if (dx.abs() < 4 && dy.abs() < 4) return;
    var angle = atan2(dx, -dy);
    if (angle < 0) angle += 2 * pi;
    final raw = 1 + (angle - dialGapHalf) / dialSweep * (dialDetents - 1);
    final beyond = raw < 1 || raw > dialDetents;
    final next = raw.round().clamp(1, dialDetents);
    if (beyond && !_atStop) {
      // Slammed into the stopper: one heavy thud, no detent tick.
      _atStop = true;
      _haptic(HapticFeedback.heavyImpact);
    } else if (!beyond && next != widget.days) {
      // Detent tick — medium impact so the turning feels tactile.
      _haptic(HapticFeedback.mediumImpact);
    }
    if (!beyond) _atStop = false;
    if (next != widget.days) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, 300.0);
        final size = Size(side, side);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handle(d.localPosition, size),
          onTapUp: (_) => widget.onReleased(),
          onPanStart: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          onPanEnd: (_) => widget.onReleased(),
          child: SizedBox.fromSize(
            size: size,
            child: Stack(
              children: [
                CustomPaint(
                  key: const ValueKey('day_dial'),
                  size: size,
                  painter: _DialPainter(
                      days: widget.days, scheme: theme.colorScheme),
                ),
                Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer,
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${widget.days}',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          'Days',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  final int days;
  final ColorScheme scheme;

  _DialPainter({required this.days, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    // Dial face.
    canvas.drawCircle(
        center, radius, Paint()..color = scheme.surfaceContainerHighest);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.outlineVariant,
    );

    // Track arc along the sweep — the scale is an arc, not a circle.
    // Canvas arcs measure from 3 o'clock, so shift by -90°.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 14),
      dialAngleForDay(1) - pi / 2,
      dialSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = scheme.outlineVariant,
    );

    // 30 detents; majors every 5 (plus 1) carry numeric labels.
    for (var d = 1; d <= dialDetents; d++) {
      final angle = dialAngleForDay(d);
      final dir = Offset(sin(angle), -cos(angle));
      final major = d == 1 || d % 5 == 0;
      final active = d == days;
      final len = active ? 20.0 : (major ? 16.0 : 8.0);
      final p1 = center + dir * (radius - 14 - len);
      final p2 = center + dir * (radius - 14);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = active ? 4 : (major ? 3 : 1.5)
          ..strokeCap = StrokeCap.round
          ..color = active ? scheme.primary : scheme.outline,
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$d',
            style: TextStyle(
              color: active ? scheme.primary : scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pos =
            center + dir * (radius - 52) - Offset(tp.width / 2, tp.height / 2);
        tp.paint(canvas, pos);
      }
    }

    // Stopper: a physical block in the dead-zone gap, just clockwise past
    // the 30 tick. The knob hits it instead of wrapping around to 1.
    final stopperCenter = center + const Offset(0, -1) * (radius - 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: stopperCenter, width: 14, height: 32),
        const Radius.circular(7),
      ),
      Paint()..color = scheme.tertiary,
    );

    // Knob dot on the active detent.
    final knobAngle = dialAngleForDay(days);
    final knobDir = Offset(sin(knobAngle), -cos(knobAngle));
    canvas.drawCircle(
        center + knobDir * (radius - 14), 8, Paint()..color = scheme.primary);
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.days != days || old.scheme != scheme;
}
