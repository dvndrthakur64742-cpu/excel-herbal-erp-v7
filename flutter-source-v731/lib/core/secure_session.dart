import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureSession {
  const SecureSession(this._storage);
  final FlutterSecureStorage _storage;
  static const _access = 'eh7_access_token';
  static const _refresh = 'eh7_refresh_token';

  Future<String?> accessToken() => _storage.read(key: _access);
  Future<String?> refreshToken() => _storage.read(key: _refresh);
  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _access, value: accessToken);
    await _storage.write(key: _refresh, value: refreshToken);
  }
  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
  }
}
