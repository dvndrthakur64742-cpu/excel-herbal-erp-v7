import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureSession {
  const SecureSession(this._storage);

  final FlutterSecureStorage _storage;

  static const _access = 'eh7_access_token';
  static const _refresh = 'eh7_refresh_token';
  static const _mutationJournal = 'eh7_uncertain_mutations_v1';

  Future<String?> accessToken() => _storage.read(key: _access);
  Future<String?> refreshToken() => _storage.read(key: _refresh);

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _access, value: accessToken);
    await _storage.write(key: _refresh, value: refreshToken);
  }

  Future<Map<String, dynamic>> uncertainMutations() async {
    final raw = await _storage.read(key: _mutationJournal);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A corrupt local retry journal must never block business operations.
    }
    return <String, dynamic>{};
  }

  Future<void> saveUncertainMutations(Map<String, dynamic> journal) async {
    if (journal.isEmpty) {
      await _storage.delete(key: _mutationJournal);
      return;
    }
    await _storage.write(key: _mutationJournal, value: jsonEncode(journal));
  }

  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _mutationJournal);
  }
}