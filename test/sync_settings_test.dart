import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/store/sync_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SyncSettings> mockSettings(
    [Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SyncSettings(await SharedPreferences.getInstance());
}

void main() {
  test('refresh cooldown defaults to 2 minutes', () async {
    final settings = await mockSettings();
    expect(settings.refreshCooldownMinutes, 2);
  });

  test('refresh cooldown persists and clamps to 0–60', () async {
    final settings = await mockSettings();
    await settings.setRefreshCooldownMinutes(5);
    expect(settings.refreshCooldownMinutes, 5);
    await settings.setRefreshCooldownMinutes(99);
    expect(settings.refreshCooldownMinutes, 60);
    await settings.setRefreshCooldownMinutes(-1);
    expect(settings.refreshCooldownMinutes, 0);
  });
}
