import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_paths.dart';
import 'app_config.dart';
import 'secure_session.dart';

class ApiException implements Exception {
  const ApiException(
    this.code,
    this.message, [
    this.statusCode,
    this.requestId,
  ]);

  final String code;
  final String message;
  final int? statusCode;
  final String? requestId;

  bool get isAuthenticationFailure => statusCode == 401;
  bool get isPermissionFailure => statusCode == 403;

  @override
  String toString() => message;
}

class _MutationKey {
  const _MutationKey(this.value, this.createdAt);

  final String value;
  final DateTime createdAt;
}

class ApiClient {
  ApiClient(this.session)
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
          headers: const {'Accept': 'application/json'},
        ),
      );

  final SecureSession session;
  final Dio dio;
  final Random _random = Random.secure();
  Future<bool>? _refreshFuture;

  static const _uncertainMutationTtl = Duration(minutes: 30);

  static String get deviceLabel =>
      kIsWeb ? 'Excel Herbal ERP Web' : 'Excel Herbal ERP Android';

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) => _request('GET', path, query: query, authenticated: authenticated);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    bool idempotent = true,
    bool authenticated = true,
  }) => _request(
    'POST',
    path,
    data: data,
    idempotent: idempotent,
    authenticated: authenticated,
  );

  Future<dynamic> uploadFile(
    String path, {
    required String filePath,
    required String filename,
    required Map<String, dynamic> fields,
  }) => _uploadMultipart(
    path,
    filename: filename,
    fields: fields,
    fileFactory: () => MultipartFile.fromFile(filePath, filename: filename),
  );

  Future<dynamic> uploadBytes(
    String path, {
    required Uint8List bytes,
    required String filename,
    required Map<String, dynamic> fields,
  }) => _uploadMultipart(
    path,
    filename: filename,
    fields: fields,
    fileFactory: () async => MultipartFile.fromBytes(bytes, filename: filename),
  );

  Future<dynamic> _uploadMultipart(
    String path, {
    required String filename,
    required Map<String, dynamic> fields,
    required Future<MultipartFile> Function() fileFactory,
  }) async {
    final headers = <String, dynamic>{};
    final token = await session.accessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    headers['X-Idempotency-Key'] = _requestKey();

    Future<Response<dynamic>> send() async {
      final form = FormData.fromMap({
        ...fields,
        'file': await fileFactory(),
      });
      return dio.post<dynamic>(
        path,
        data: form,
        options: Options(headers: headers, contentType: 'multipart/form-data'),
      );
    }

    try {
      final response = await send();
      return _unwrap(response.data, response.statusCode);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 && await _refresh()) {
        final refreshed = await session.accessToken();
        if (refreshed != null && refreshed.isNotEmpty) {
          headers['Authorization'] = 'Bearer $refreshed';
        }
        try {
          final response = await send();
          return _unwrap(response.data, response.statusCode);
        } on DioException catch (second) {
          throw _dioException(second);
        }
      }
      throw _dioException(error);
    }
  }

  Future<dynamic> login(String mobile, String password) async {
    final data = await post(
      ApiPaths.login,
      data: {
        'mobile': mobile.replaceAll(RegExp(r'\s+'), ''),
        'password': password,
        'device': deviceLabel,
      },
      idempotent: false,
      authenticated: false,
    );
    final map = Map<String, dynamic>.from(data as Map);
    await session.save(
      accessToken: '${map['access_token']}',
      refreshToken: '${map['refresh_token']}',
    );
    return map;
  }

  Future<void> logout() async {
    try {
      await post(ApiPaths.logout, data: const {}, idempotent: false);
    } catch (_) {
      // Local logout still proceeds when the network is unavailable.
    }
    await session.clear();
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? data,
    bool idempotent = false,
    bool authenticated = true,
    bool retried = false,
    String? retainedMutationKey,
  }) async {
    final headers = <String, dynamic>{};
    if (authenticated) {
      final token = await session.accessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    String? fingerprint;
    String? mutationKey;
    if (idempotent && method != 'GET') {
      fingerprint = _mutationFingerprint(method, path, data);
      final retained = retainedMutationKey == null
          ? await _loadRetainedMutation(fingerprint)
          : null;
      mutationKey = retainedMutationKey ?? retained?.value ?? _requestKey();
      headers['X-Idempotency-Key'] = mutationKey;
    }

    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      if (fingerprint != null) await _clearRetainedMutation(fingerprint);
      return _unwrap(response.data, response.statusCode);
    } on DioException catch (error) {
      if (authenticated &&
          !retried &&
          error.response?.statusCode == 401 &&
          await _refresh()) {
        return _request(
          method,
          path,
          query: query,
          data: data,
          idempotent: idempotent,
          authenticated: authenticated,
          retried: true,
          retainedMutationKey: mutationKey,
        );
      }

      if (fingerprint != null && mutationKey != null) {
        if (_isUncertainNetworkFailure(error)) {
          await _saveRetainedMutation(fingerprint, mutationKey);
        } else {
          await _clearRetainedMutation(fingerprint);
        }
      }
      throw _dioException(error);
    }
  }

  ApiException _dioException(DioException error) {
    final body = error.response?.data;
    final requestId = _responseRequestId(error.response, body);
    if (body is Map && body['error'] is Map) {
      final er = Map<String, dynamic>.from(body['error'] as Map);
      return ApiException(
        '${er['code'] ?? 'api_error'}',
        '${er['message'] ?? 'Request failed'}',
        error.response?.statusCode,
        requestId,
      );
    }
    return ApiException(
      'network_error',
      _networkMessage(error),
      error.response?.statusCode,
      requestId,
    );
  }

  dynamic _unwrap(dynamic body, int? statusCode) {
    if (body is Map && body['ok'] == true) return body['data'];
    if (body is Map && body['error'] is Map) {
      final er = Map<String, dynamic>.from(body['error'] as Map);
      final requestId = '${body['request_id'] ?? ''}'.trim();
      throw ApiException(
        '${er['code'] ?? 'api_error'}',
        '${er['message'] ?? 'Request failed'}',
        statusCode,
        requestId.isEmpty ? null : requestId,
      );
    }
    return body;
  }

  Future<bool> _refresh() {
    final existing = _refreshFuture;
    if (existing != null) return existing;
    final future = _performRefresh();
    _refreshFuture = future;
    return future.whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _performRefresh() async {
    final refresh = await session.refreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final response = await dio.post<dynamic>(
        ApiPaths.refresh,
        data: {'refresh_token': refresh, 'device': deviceLabel},
      );
      final data = _unwrap(response.data, response.statusCode);
      final map = Map<String, dynamic>.from(data as Map);
      await session.save(
        accessToken: '${map['access_token']}',
        refreshToken: '${map['refresh_token']}',
      );
      return true;
    } on DioException catch (error) {
      // Only an explicit refresh-token rejection invalidates the local session.
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        await session.clear();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _isUncertainNetworkFailure(DioException error) =>
      error.response == null &&
      (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown);

  Future<_MutationKey?> _loadRetainedMutation(String fingerprint) async {
    try {
      final journal = await session.uncertainMutations();
      final key = _mutationJournalKey(fingerprint);
      final raw = journal[key];
      if (raw is! Map) return null;
      final item = Map<String, dynamic>.from(raw);
      final value = '${item['key'] ?? ''}'.trim();
      final createdAt = DateTime.tryParse('${item['created_at'] ?? ''}');
      if (value.isEmpty || createdAt == null) {
        journal.remove(key);
        await session.saveUncertainMutations(journal);
        return null;
      }
      if (createdAt.isBefore(DateTime.now().subtract(_uncertainMutationTtl))) {
        journal.remove(key);
        await session.saveUncertainMutations(journal);
        return null;
      }
      return _MutationKey(value, createdAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRetainedMutation(
    String fingerprint,
    String mutationKey,
  ) async {
    try {
      final journal = await session.uncertainMutations();
      journal[_mutationJournalKey(fingerprint)] = {
        'key': mutationKey,
        'created_at': DateTime.now().toIso8601String(),
      };
      await session.saveUncertainMutations(journal);
    } catch (_) {
      // Persistence failure must not hide the original request result.
    }
  }

  Future<void> _clearRetainedMutation(String fingerprint) async {
    try {
      final journal = await session.uncertainMutations();
      final removed = journal.remove(_mutationJournalKey(fingerprint));
      if (removed != null) await session.saveUncertainMutations(journal);
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  String _mutationJournalKey(String fingerprint) =>
      sha256.convert(utf8.encode(fingerprint)).toString();

  String _mutationFingerprint(
    String method,
    String path,
    Map<String, dynamic>? data,
  ) =>
      '$method|$path|${jsonEncode(_canonical(data ?? const <String, dynamic>{}))}';

  dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) {
      return value.map(_canonical).toList(growable: false);
    }
    return value;
  }

  String _requestKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 31)}';

  String? _responseRequestId(Response<dynamic>? response, dynamic body) {
    final fromHeader = response?.headers.value('x-request-id')?.trim();
    if (fromHeader != null && fromHeader.isNotEmpty) return fromHeader;
    if (body is Map) {
      final fromBody = '${body['request_id'] ?? ''}'.trim();
      if (fromBody.isNotEmpty) return fromBody;
    }
    return null;
  }

  String _networkMessage(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Network slow hai. Retry karein.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Internet connection available nahi hai.';
    }
    if (error.response != null) {
      return 'Server error (${error.response?.statusCode ?? '-'}). Retry karein.';
    }
    return 'Server se response nahi mila. Retry karein.';
  }
}
