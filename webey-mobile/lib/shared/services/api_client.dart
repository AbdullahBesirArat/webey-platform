import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/storage/secure_token_storage.dart';
import 'app_logger.dart';
import 'result.dart';

const webeyNetworkDisabledMessage =
    'Network calls are disabled in widget tests. '
    'Use fake repositories or integration tests.';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.isUnauthorized = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final bool isUnauthorized;

  @override
  String toString() => message;
}

class ApiClient {
  const ApiClient({
    http.Client? httpClient,
    SecureTokenStorage? tokenStorage,
    String? baseUrl,
  }) : _httpClient = httpClient,
       _tokenStorage = tokenStorage ?? const SecureTokenStorage(),
       _baseUrl = baseUrl;

  static bool debugDisableNetworkForTests = false;

  final http.Client? _httpClient;
  final SecureTokenStorage _tokenStorage;
  final String? _baseUrl;

  http.Client get _client => _httpClient ?? http.Client();

  String get baseUrl => _baseUrl ?? ApiConfig.mobileBaseUrl;

  Future<Result<Map<String, Object?>>> get(String path) async {
    try {
      final data = await getData(path);
      return Result.ok(data);
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    }
  }

  Future<Result<Map<String, Object?>>> post(
    String path, {
    Map<String, Object?> body = const {},
  }) async {
    try {
      final data = await postData(path, body: body);
      return Result.ok(data);
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    }
  }

  Future<Map<String, Object?>> getData(String path) {
    return _send('GET', path);
  }

  Future<Map<String, Object?>> postData(
    String path, {
    Map<String, Object?> body = const {},
  }) {
    return _send('POST', path, body: body);
  }

  Future<Map<String, Object?>> multipartData(
    String path, {
    required String fileField,
    required String filePath,
    Map<String, String> fields = const {},
  }) async {
    final uri = _uri(path);
    _throwIfNetworkDisabled('POST', uri);
    AppLogger.debug('POST multipart $uri');

    try {
      final token = await _tokenStorage.readToken();
      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..fields.addAll(fields);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));

      final streamed = await _client
          .send(request)
          .timeout(ApiConfig.receiveTimeout);
      final response = await http.Response.fromStream(streamed);
      return _parseResponse(response);
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Sunucudan beklenmeyen yanıt alındı');
    } on Exception catch (error) {
      AppLogger.error('Multipart API request failed', error);
      throw const ApiException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?> body = const {},
  }) async {
    final uri = _uri(path);
    _throwIfNetworkDisabled(method, uri);
    AppLogger.debug('$method $uri');

    try {
      final token = await _tokenStorage.readToken();
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: jsonEncode(body)),
        _ => throw ApiException('Desteklenmeyen istek metodu'),
      };

      final response = await request.timeout(ApiConfig.receiveTimeout);
      return _parseResponse(response);
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Sunucudan beklenmeyen yanıt alındı');
    } on Exception catch (error) {
      AppLogger.error('API request failed', error);
      throw const ApiException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }

  Uri _uri(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$cleanPath');
  }

  void _throwIfNetworkDisabled(String method, Uri uri) {
    if (!debugDisableNetworkForTests) {
      return;
    }

    throw ApiException('$webeyNetworkDisabledMessage Attempted: $method $uri');
  }

  Future<Map<String, Object?>> _parseResponse(http.Response response) async {
    final statusCode = response.statusCode;
    final contentType = response.headers['content-type'] ?? '';
    final bodyText = response.bodyBytes.isEmpty
        ? ''
        : utf8.decode(response.bodyBytes, allowMalformed: true);
    final trimmed = _stripBom(bodyText).trimLeft();
    AppLogger.debug(
      'API response status=$statusCode content-type=$contentType body=${_snippet(trimmed)}',
    );

    if (trimmed.isEmpty) {
      throw ApiException(
        'Sunucu boş yanıt döndürdü. Lütfen tekrar deneyin.',
        statusCode: statusCode,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (error) {
      AppLogger.warning(
        'Invalid JSON response status=$statusCode content-type=$contentType '
        'error=${error.message} body=${_snippet(trimmed)}',
      );
      throw ApiException(
        _invalidJsonMessage(statusCode, trimmed),
        statusCode: statusCode,
        code: statusCode == 404 ? 'service_not_ready' : 'invalid_json',
      );
    }

    if (decoded is! Map) {
      throw ApiException(
        'Sunucu geçersiz yanıt döndürdü. Lütfen tekrar deneyin.',
        statusCode: statusCode,
      );
    }

    final payload = Map<String, Object?>.from(decoded);
    final ok = payload['ok'] == true;

    if (ok) {
      final data = payload['data'];
      if (data is Map) {
        return Map<String, Object?>.from(data);
      }
      return {'value': data};
    }

    final message =
        _errorMessage(payload['error']) ??
        payload['message']?.toString() ??
        _statusMessage(statusCode) ??
        'İşlem tamamlanamadı';
    final code = payload['code']?.toString();
    final isUnauthorized = statusCode == 401;

    if (isUnauthorized) {
      await _tokenStorage.clearAll();
    }

    throw ApiException(
      message,
      statusCode: statusCode,
      code: code,
      isUnauthorized: isUnauthorized,
    );
  }

  static String _stripBom(String value) {
    if (value.startsWith('\uFEFF')) return value.substring(1);
    return value;
  }

  static String _snippet(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 300) return compact;
    return '${compact.substring(0, 300)}...';
  }

  static String? _errorMessage(Object? error) {
    if (error is Map) {
      final message = error['message'] ?? error['error'];
      return message?.toString();
    }
    return error?.toString();
  }

  static String _invalidJsonMessage(int statusCode, String body) {
    final lower = body.toLowerCase();
    if (statusCode == 404) {
      return 'İstenen servis sunucuda bulunamadı.';
    }
    if (lower.contains('<html') || lower.contains('<!doctype')) {
      return 'Sunucu geçersiz yanıt döndürdü. Lütfen tekrar deneyin.';
    }
    return 'Sunucu geçersiz yanıt döndürdü. Lütfen tekrar deneyin.';
  }

  static String? _statusMessage(int statusCode) {
    return switch (statusCode) {
      401 => 'Oturum süreniz dolmuş. Lütfen tekrar giriş yapın.',
      404 => 'İstenen servis sunucuda bulunamadı.',
      413 => 'Dosya çok büyük. En fazla 10 MB yükleyebilirsiniz.',
      415 => 'Bu dosya türü desteklenmiyor. JPG, PNG veya WebP yükleyin.',
      _ => null,
    };
  }
}
