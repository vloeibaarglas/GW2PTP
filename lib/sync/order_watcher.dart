/// Fill detection for buy/sell orders.
///
/// Pure logic, no I/O: given the history transactions observed since the
/// last tick, produce one [FillEvent] per filled order. Only confirmed
/// fills (present in the transaction history) generate events — an order
/// that merely vanished from the listing was cancelled by the user and
/// stays silent.
library;

/// A single confirmed fill of one of the user's orders.
class FillEvent {
  /// 'buy' or 'sell'.
  final String side;
  final int itemId;
  final int quantity;
  final int pricePerUnit;

  const FillEvent({
    required this.side,
    required this.itemId,
    required this.quantity,
    required this.pricePerUnit,
  });

  int get total => quantity * pricePerUnit;
}

/// One row from /v2/commerce/transactions/history/{buys,sells}.
class HistoryFill {
  final int id;
  final int itemId;
  final int quantity;
  final int price;

  const HistoryFill({
    required this.id,
    required this.itemId,
    required this.quantity,
    required this.price,
  });

  factory HistoryFill.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    return HistoryFill(
      id: asInt(json['id']),
      itemId: asInt(json['item_id']),
      quantity: asInt(json['quantity']),
      price: asInt(json['price']),
    );
  }
}

/// Returns the fills in [history] newer than [lastSeenId], newest last.
/// Malformed rows are skipped.
List<FillEvent> detectFills(
  String side,
  List<Map<String, dynamic>> history,
  int lastSeenId,
) {
  final events = <FillEvent>[];
  for (final row in history) {
    final fill = HistoryFill.fromJson(row);
    if (fill.id <= lastSeenId) continue;
    if (fill.itemId <= 0 || fill.quantity <= 0 || fill.price <= 0) continue;
    events.add(
      FillEvent(
        side: side,
        itemId: fill.itemId,
        quantity: fill.quantity,
        pricePerUnit: fill.price,
      ),
    );
  }
  // History is newest-first; notify oldest-first so the shade reads
  // chronologically.
  return events.reversed.toList();
}

/// Highest history id in [history], for checkpointing.
int maxHistoryId(List<Map<String, dynamic>> history) {
  var max = 0;
  for (final row in history) {
    final id = row['id'];
    final v = id is int ? id : (id is num ? id.toInt() : 0);
    if (v > max) max = v;
  }
  return max;
}
