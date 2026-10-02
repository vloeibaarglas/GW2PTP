/// Relative timestamps: "just now", "5 min ago", "3 h ago", "2 days ago".
library;

String timeAgo(DateTime? ts) {
  if (ts == null) return '';
  final age = DateTime.now().difference(ts);
  if (age.isNegative || age < const Duration(minutes: 1)) return 'Just Now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes} Min Ago';
  if (age < const Duration(days: 1)) return '${age.inHours} Hr Ago';
  final d = age.inDays;
  return d == 1 ? '1 Day Ago' : '$d Days Ago';
}
