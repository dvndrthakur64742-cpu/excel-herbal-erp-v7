import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_paths.dart';
import 'app_config.dart';
import 'document_download.dart';
import 'mutation_fingerprint.dart';
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

  void _requireSafeApiTarget() {
    if (AppConfig.unsafeApiTarget) {
      throw const ApiException(
        'unsafe_api_environment',
        'ERP app build targets the wrong server. Contact the administrator.',
        403,
      );
    }
  }

  static const _uncertainMutationTtl = Duration(minutes: 30);

  static String get deviceLabel =>
      kIsWeb ? 'Excel Herbal ERP Web' : 'Excel Herbal ERP Android';

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    final data = await _request(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
    if (path == ApiPaths.availableStock && data is List) {
      return data.map((row) {
        if (row is! Map) return row;
        final normalized = Map<String, dynamic>.from(row);
        normalized.putIfAbsent('custodian_key', () => 0);
        return normalized;
      }).toList(growable: false);
    }
    return data;
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    bool idempotent = true,
    bool authenticated = true,
  }) =>
      _request(
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
  }) =>
      _uploadMultipart(
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
  }) =>
      _uploadMultipart(
        path,
        filename: filename,
        fields: fields,
        fileFactory: () async =>
            MultipartFile.fromBytes(bytes, filename: filename),
      );

  Future<dynamic> _uploadMultipart(
    String path, {
    required String filename,
    required Map<String, dynamic> fields,
    required Future<MultipartFile> Function() fileFactory,
  }) async {
    _requireSafeApiTarget();
    final headers = <String, dynamic>{};
    final token = await session.accessToken();
    if (token != null && token.isNotEmpty) {
      headers.addAll(bearerHeaders(token));
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
          headers.addAll(bearerHeaders(refreshed));
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

  Future<({Uint8List bytes, String filename, String mimeType})>
      downloadPrivateDocument(String url, {bool retried = false}) async {
    _requireSafeApiTarget();
    final uri = privateDocumentUri(dio.options.baseUrl, url);
    final token = await session.accessToken();
    if (token == null || token.isEmpty) {
      throw const ApiException('not_authenticated', 'Please sign in again.', 401);
    }
    try {
      final response = await dio.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
          headers: {
            ...bearerHeaders(token),
            'Accept': 'application/pdf,image/jpeg,image/png,image/webp',
          },
        ),
      );
      final mime = (response.headers.value('content-type') ?? '')
          .split(';').first.trim().toLowerCase();
      final bytes = response.data;
      if (response.statusCode != 200 ||
          !{'application/pdf', 'image/jpeg', 'image/png', 'image/webp'}.contains(mime) ||
          bytes == null || bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw const ApiException('document_response_invalid',
            'The server did not return a supported document.');
      }
      return (
        bytes: Uint8List.fromList(bytes),
        filename: documentFilename(response.headers.value('content-disposition'), mime),
        mimeType: mime,
      );
    } on DioException catch (error) {
      if (!retried && error.response?.statusCode == 401 && await _refresh()) {
        return downloadPrivateDocument(url, retried: true);
      }
      final body = error.response?.data;
      if (body is List<int>) {
        try { error.response?.data = jsonDecode(utf8.decode(body)); }
        on FormatException { /* Use the normal network error if it is not JSON. */ }
      }
      throw _dioException(error);
    }
  }

  Future<dynamic> login(String mobile, String password) async {
    final deviceId = await session.deviceId();
    final data = await post(
      ApiPaths.login,
      data: {
        'mobile': mobile.replaceAll(RegExp(r'\s+'), ''),
        'password': password,
        'device': deviceLabel,
        'device_id': deviceId,
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
    _requireSafeApiTarget();
    final headers = <String, dynamic>{};
    if (authenticated) {
      final token = await session.accessToken();
      if (token != null && token.isNotEmpty) {
        headers.addAll(bearerHeaders(token));
      }
    }

    String? fingerprint;
    String? mutationKey;
    if (idempotent && method != 'GET') {
      fingerprint = buildMutationFingerprint(
        method,
        path,
        query: query,
        data: data,
      );
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
    _requireSafeApiTarget();
    final refresh = await session.refreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    final generation = await session.sessionGeneration();
    try {
      final deviceId = await session.deviceId();
      final response = await dio.post<dynamic>(
        ApiPaths.refresh,
        data: {
          'refresh_token': refresh,
          'device': deviceLabel,
          'device_id': deviceId,
        },
      );
      final data = _unwrap(response.data, response.statusCode);
      final map = Map<String, dynamic>.from(data as Map);
      await session.save(
        accessToken: '${map['access_token']}',
        refreshToken: '${map['refresh_token']}',
      );
      return true;
    } on DioException catch (error) {
      // A second browser tab can refresh the shared web session first. In that
      // case this request may be rejected because it used the now-rotated
      // refresh token. Never clear the newer shared tokens written by the
      // winning tab; let the original API request retry with them instead.
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        if (await _adoptPeerRefresh(refresh, generation)) {
          return true;
        }
        await session.clear();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _adoptPeerRefresh(
    String attemptedRefresh,
    String? attemptedGeneration,
  ) async {
    // Browser tabs share the web secure-storage namespace. One tab may win the
    // refresh-token rotation while another is still receiving the 401 for the
    // old token. The session generation is written only after the complete new
    // token pair, so wait for that durable peer write before clearing storage.
    // Let a slower winning browser tab finish publishing its rotated token pair
    // before a losing tab concludes that shared credentials are invalid.
    for (var attempt = 0; attempt < 61; attempt++) {
      final latestGeneration = await session.sessionGeneration();
      final latestRefresh = await session.refreshToken();
      final peerCompleted =
          sessionGenerationWasRotated(attemptedGeneration, latestGeneration);
      final refreshChanged =
          refreshTokenWasRotated(attemptedRefresh, latestRefresh);
      if (peerCompleted || refreshChanged) {
        final latestAccess = await session.accessToken();
        if (latestAccess != null &&
            latestAccess.isNotEmpty &&
            latestRefresh != null &&
            latestRefresh.trim().isNotEmpty) {
          return true;
        }
      }
      if (attempt < 60) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return false;
  }

  @visibleForTesting
  static Map<String, String> bearerHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'X-EH7-Authorization': 'Bearer $token',
      };

  @visibleForTesting
  static bool refreshTokenWasRotated(
    String attemptedRefresh,
    String? latestRefresh,
  ) {
    final latest = latestRefresh?.trim() ?? '';
    return latest.isNotEmpty && latest != attemptedRefresh;
  }

  @visibleForTesting
  static bool sessionGenerationWasRotated(
    String? attemptedGeneration,
    String? latestGeneration,
  ) {
    final attempted = attemptedGeneration?.trim() ?? '';
    final latest = latestGeneration?.trim() ?? '';
    return latest.isNotEmpty && latest != attempted;
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