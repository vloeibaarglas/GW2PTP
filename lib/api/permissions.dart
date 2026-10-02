/// The GW2 API permissions this app needs, and what each one unlocks.
/// Shown in Settings and used for the on-entry permission check.
library;

/// permission -> user-facing description of what breaks without it.
const Map<String, String> requiredApiPermissions = {
  'wallet': 'Coin balance in the app bar',
  'tradingpost': 'Delivery box, open buy/sell orders, and fill history',
  'inventories':
      'Bank, crafting materials, shared slots, character bags and equipped gear',
  'characters': 'Character list (needed to load bags and equipped gear)',
};

/// Permissions from [requiredApiPermissions] absent from [granted].
List<String> missingApiPermissions(List<String> granted) {
  final have = granted.toSet();
  return [
    for (final p in requiredApiPermissions.keys)
      if (!have.contains(p)) p,
  ];
}

/// User-facing display name for a permission key. Known keys get proper
/// labels; anything unknown falls back to a first-letter capital.
String displayPermissionName(String key) {
  const labels = {
    'wallet': 'Wallet',
    'tradingpost': 'Trading Post',
    'inventories': 'Inventories',
    'characters': 'Characters',
  };
  final label = labels[key];
  if (label != null) return label;
  if (key.isEmpty) return key;
  return key[0].toUpperCase() + key.substring(1);
}
