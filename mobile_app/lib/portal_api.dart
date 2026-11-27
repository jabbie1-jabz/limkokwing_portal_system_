import 'dart:convert';
import 'dart:io';

const portalBaseUrl = String.fromEnvironment(
  'PORTAL_URL',
  defaultValue: 'http://127.0.0.1:5000/',
);

class PortalApiException implements Exception {
  const PortalApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class PortalApi {
  PortalApi({HttpClient? client})
    : _client = client ?? HttpClient(),
      _baseUri = Uri.parse(portalBaseUrl);

  final HttpClient _client;
  final Uri _baseUri;
  String? _token;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String campusId = '',
    String campusCode = '',
  }) async {
    final result = await _request(
      'POST',
      '/api/mobile/login',
      body: {
        'email': email,
        'password': password,
        'campus_id': campusId,
        'campus_code': campusCode,
      },
    );
    _token = result['token'] as String;
    return _map(result['user']);
  }

  Future<String> register({
    required String fullName,
    required String campusId,
    required String campusCode,
    required String studentId,
    required String email,
    required String password,
  }) async {
    final result = await _request(
      'POST',
      '/api/mobile/register',
      body: {
        'full_name': fullName,
        'campus_id': campusId,
        'campus_code': campusCode,
        'student_id': studentId,
        'email': email,
        'password': password,
      },
    );
    return result['message'] as String;
  }

  Future<void> logout() async {
    try {
      if (_token != null) {
        await _request('POST', '/api/mobile/logout');
      }
    } finally {
      _token = null;
    }
  }

  Future<Map<String, dynamic>> loadRequests() async {
    return _request('GET', '/api/mobile/requests');
  }

  Future<Map<String, dynamic>> loadRequest(int id) async {
    return _request('GET', '/api/mobile/requests/$id');
  }

  Future<void> createRequest({
    required String category,
    required String serviceType,
    required String description,
    required String priority,
  }) async {
    await _request(
      'POST',
      '/api/mobile/requests',
      body: {
        'category': category,
        'service_type': serviceType,
        'description': description,
        'priority': priority,
      },
    );
  }

  Future<void> updateRequest({
    required int id,
    required String status,
    required String priority,
    required String note,
    required bool isInternal,
  }) async {
    await _request(
      'POST',
      '/api/mobile/requests/$id/update',
      body: {
        'status': status,
        'priority': priority,
        'note': note,
        'is_internal': isInternal,
      },
    );
  }

  Future<List<Map<String, dynamic>>> loadUsers() async {
    final result = await _request('GET', '/api/mobile/users');
    return _list(result['users']);
  }

  Future<void> verifyStudent(int id) async {
    await _request('POST', '/api/mobile/users/$id/verify');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(method, _baseUri.resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_token case final token?) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final dynamic decoded = responseBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(responseBody);
    final result = _map(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PortalApiException(
        result['error'] as String? ?? 'The portal request failed.',
        statusCode: response.statusCode,
      );
    }
    return result;
  }

  void close() {
    _client.close(force: true);
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('The portal returned an invalid response.');
  }

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) {
      throw const FormatException('The portal returned an invalid list.');
    }
    return value.map(_map).toList();
  }
}
