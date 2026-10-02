/// Absolute local clock time for sync timestamps: "3:42 PM" when the
/// timestamp is today, "9/29 3:42 PM" otherwise. Always the device's
/// local timezone.
library;

String formatClockTime(DateTime dt) {
  final now = DateTime.now();
  final h = dt.hour;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  final mm = dt.minute.toString().padLeft(2, '0');
  final ampm = h < 12 ? 'AM' : 'PM';
  final time = '$hour12:$mm $ampm';
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  return sameDay ? time : '${dt.month}/${dt.day} $time';
}
