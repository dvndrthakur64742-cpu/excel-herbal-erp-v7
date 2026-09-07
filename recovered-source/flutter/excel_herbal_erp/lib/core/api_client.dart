import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'api_paths.dart';
import 'app_config.dart';
import 'secure_session.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, [this.statusCode]);
  final String code;
  final String message;
  final int? statusCode;

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
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            headers: const {'Accept': 'application/json'},
          ),
        );

  final SecureSession session;
  final Dio dio;
  final Random _random = Random.secure();
  final Map<String, _MutationKey> _uncertainMutations = {};
  final Map<String, Future<dynamic>> _inFlightMutations = {};
  Future<bool>? _refreshFuture;

  static const _uncertainMutationTtl = Duration(minutes: 5);

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _request('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    bool idempotent = true,
    bool authenticated = true,
  }) {
    if (!idempotent) {
      return _request(
        'POST',
        path,
        data: data,
        idempotent: false,
        authenticated: authenticated,
      );
    }
    final fingerprint = _mutationFingerprint('POST', path, data);
    final existing = _inFlightMutations[fingerprint];
    if (existing != null) return existing;
    final future = _request(
      'POST',
      path,
      data: data,
      idempotent: true,
      authenticated: authenticated,
    );
    _inFlightMutations[fingerprint] = future;
    return future.whenComplete(() {
      if (identical(_inFlightMutations[fingerprint], future)) {
        _inFlightMutations.remove(fingerprint);
      }
    });
  }

  Future<dynamic> login(String mobile, String password) async {
    final data = await post(
      ApiPaths.login,
      data: {'mobile': mobile, 'password': password, 'device': 'Flutter'},
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
    _uncertainMutations.clear();
    _inFlightMutations.clear();
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
      _pruneUncertainMutations();
      fingerprint = _mutationFingerprint(method, path, data);
      final retained = _uncertainMutations[fingerprint];
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
      if (fingerprint != null) _uncertainMutations.remove(fingerprint);
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
          _uncertainMutations[fingerprint] =
              _MutationKey(mutationKey, DateTime.now());
        } else {
          _uncertainMutations.remove(fingerprint);
        }
      }

      final body = error.response?.data;
      if (body is Map && body['error'] is Map) {
        final er = Map<String, dynamic>.from(body['error'] as Map);
        throw ApiException(
          '${er['code'] ?? 'api_error'}',
          '${er['message'] ?? 'Request failed'}',
          error.response?.statusCode,
        );
      }
      throw ApiException(
        'network_error',
        _networkMessage(error),
        error.response?.statusCode,
      );
    }
  }

  dynamic _unwrap(dynamic body, int? statusCode) {
    if (body is Map && body['ok'] == true) return body['data'];
    if (body is Map && body['error'] is Map) {
      final er = Map<String, dynamic>.from(body['error'] as Map);
      throw ApiException(
        '${er['code'] ?? 'api_error'}',
        '${er['message'] ?? 'Request failed'}',
        statusCode,
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
        data: {'refresh_token': refresh, 'device': 'Flutter'},
      );
      final data = _unwrap(response.data, response.statusCode);
      final map = Map<String, dynamic>.from(data as Map);
      await session.save(
        accessToken: '${map['access_token']}',
        refreshToken: '${map['refresh_token']}',
      );
      return true;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        _uncertainMutations.clear();
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

  void _pruneUncertainMutations() {
    final cutoff = DateTime.now().subtract(_uncertainMutationTtl);
    _uncertainMutations.removeWhere((_, item) => item.createdAt.isBefore(cutoff));
  }

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

  String _networkMessage(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Network slow hai. Retry karein.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Internet connection available nahi hai.';
    }
    return 'Server se response nahi mila. Retry karein.';
  }
}
