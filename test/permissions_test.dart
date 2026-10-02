import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/permissions.dart';

void main() {
  test('no missing permissions when all are granted', () {
    expect(
      missingApiPermissions(['wallet', 'tradingpost', 'inventories', 'characters']),
      isEmpty,
    );
  });

  test('missing permissions are reported in required order', () {
    expect(
      missingApiPermissions(['wallet']),
      ['tradingpost', 'inventories', 'characters'],
    );
  });

  test('extra unknown permissions are ignored', () {
    expect(
      missingApiPermissions(
          ['wallet', 'tradingpost', 'inventories', 'characters', 'pvp']),
      isEmpty,
    );
  });

  test('display names are capitalized', () {
    expect(displayPermissionName('wallet'), 'Wallet');
    expect(displayPermissionName('tradingpost'), 'Trading Post');
    expect(displayPermissionName('inventories'), 'Inventories');
    expect(displayPermissionName('characters'), 'Characters');
    // Unknown keys fall back to a first-letter capital, never lowercase.
    expect(displayPermissionName('unlock'), 'Unlock');
    expect(displayPermissionName(''), '');
  });
}
