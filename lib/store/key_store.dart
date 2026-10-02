/// API key storage.
///
/// The key lives in the Android Keystore via flutter_secure_storage — never
/// in plain SharedPreferences, never in logs, never shown unmasked in the
/// UI. The abstraction exists so tests can substitute an in-memory fake.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyStore {
  Future<String?> readApiKey();
  Future<void> writeApiKey(String key);
  Future<void> deleteApiKey();
}

class SecureKeyStore implements KeyStore {
  static const _keyName = 'gw2_api_key';

  final FlutterSecureStorage _storage;

  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readApiKey() async {
    try {
      final value = await _storage.read(key: _keyName);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      // Keystore hiccups (e.g. first run on a fresh profile) surface as
      // "no key", never as a crash.
      return null;
    }
  }

  @override
  Future<void> writeApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());

  @override
  Future<void> deleteApiKey() => _storage.delete(key: _keyName);
}

/// In-memory fake for widget tests.
class FakeKeyStore implements KeyStore {
  String? _key;

  FakeKeyStore([this._key]);

  @override
  Future<String?> readApiKey() async => _key;

  @override
  Future<void> writeApiKey(String key) async {
    _key = key.trim().isEmpty ? null : key.trim();
  }

  @override
  Future<void> deleteApiKey() async {
    _key = null;
  }
}
