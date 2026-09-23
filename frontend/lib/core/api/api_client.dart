import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';

/// Result type that carries either a successful value or an error message.
class ApiResult<T> {
  final T? data;
  final String? error;

  const ApiResult.success(this.data) : error = null;
  const ApiResult.failure(this.error) : data = null;

  bool get isSuccess => error == null;
}

/// Low-level HTTP client for SmartDial API communication.
///
/// All requests are routed through [AppConstants.baseUrl].
/// Protected requests attach the stored JWT as a Bearer header.
class ApiClient {
  ApiClient._();

  static final String _base = AppConstants.baseUrl;

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json',
      };

  /// Parse the error detail from a FastAPI error response.
  static String _errorDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List) return detail.map((e) => e['msg']).join(', ');
      return 'Unexpected error (${response.statusCode})';
    } catch (_) {
      return 'Unexpected error (${response.statusCode})';
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// GET /health — verify backend connectivity.
  static Future<ApiResult<Map<String, dynamic>>> health() async {
    try {
      final response = await http
          .get(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Backend unavailable: $e');
    }
  }

  /// POST /api/auth/register
  static Future<ApiResult<Map<String, dynamic>>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/api/auth/register'),
            headers: _jsonHeaders(),
            body: jsonEncode({
              'name': name,
              'email': email,
              'phone': phone,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Registration failed: $e');
    }
  }

  /// POST /api/auth/login — returns token response.
  static Future<ApiResult<Map<String, dynamic>>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/api/auth/login'),
            headers: _jsonHeaders(),
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Login failed: $e');
    }
  }

  /// GET /api/users — protected endpoint.
  static Future<ApiResult<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/api/users'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      // Include status code so callers can detect 401/403
      return ApiResult.failure('${response.statusCode}: ${_errorDetail(response)}');
    } catch (e) {
      return ApiResult.failure('Could not load users: $e');
    }
  }

  // ── Calls API ─────────────────────────────────────────────────────────────

  /// POST /api/calls/request — create a call intent.
  /// Only receiver_id is sent; caller is derived from JWT on the backend.
  static Future<ApiResult<Map<String, dynamic>>> createCallRequest({
    required int receiverId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/api/calls/request'),
            headers: await _authHeaders(),
            body: jsonEncode({'receiver_id': receiverId}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not create call request: $e');
    }
  }

  /// GET /api/calls/{request_id} — fetch a single call request.
  static Future<ApiResult<Map<String, dynamic>>> getCallRequest(
    String requestId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/api/calls/$requestId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not fetch call request: $e');
    }
  }

  /// GET /api/calls — my call requests (optionally filtered by status).
  static Future<ApiResult<Map<String, dynamic>>> getMyCallRequests({
    String? status,
  }) async {
    try {
      final uri = Uri.parse('$_base/api/calls').replace(
        queryParameters: status != null ? {'status': status} : null,
      );
      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not fetch call requests: $e');
    }
  }

  /// POST /api/calls/{request_id}/cancel — cancel a PENDING call request.
  static Future<ApiResult<Map<String, dynamic>>> cancelCallRequest(
    String requestId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/api/calls/$requestId/cancel'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not cancel call request: $e');
    }
  }

  /// POST /api/reciprocal-pairs/{pair_id}/decision/respond
  static Future<ApiResult<Map<String, dynamic>>> respondToDecision({
    required String pairId,
    required String action,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/api/reciprocal-pairs/$pairId/decision/respond'),
            headers: await _authHeaders(),
            body: jsonEncode({'action': action}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not respond to decision: $e');
    }
  }

  /// GET /api/reciprocal-pairs/{pair_id}/decision
  static Future<ApiResult<Map<String, dynamic>>> getDecision(String pairId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/api/reciprocal-pairs/$pairId/decision'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not fetch decision: $e');
    }
  }

  /// GET /api/reciprocal-pairs — fetch history of collision events
  static Future<ApiResult<List<dynamic>>> getReciprocalPairs() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/api/reciprocal-pairs'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final pairs = body['pairs'] as List<dynamic>? ?? [];
        return ApiResult.success(pairs);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not fetch collision history: $e');
    }
  }

  /// GET /api/users/me — fetch current user profile
  static Future<ApiResult<Map<String, dynamic>>> getMe() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/api/users/me'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not fetch profile: $e');
    }
  }

  /// PATCH /api/users/me/preferences — update DND, VIP, or reciprocal preferences
  static Future<ApiResult<Map<String, dynamic>>> updatePreferences({
    String? reciprocalCallPreference,
    bool? dndEnabled,
    String? vipContacts,
  }) async {
    try {
      final body = <String, dynamic>{
        if (reciprocalCallPreference != null)
          'reciprocal_call_preference': reciprocalCallPreference,
        if (dndEnabled != null) 'dnd_enabled': dndEnabled,
        if (vipContacts != null) 'vip_contacts': vipContacts,
      };

      final response = await http
          .patch(
            Uri.parse('$_base/api/users/me/preferences'),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return ApiResult.failure(_errorDetail(response));
    } catch (e) {
      return ApiResult.failure('Could not update preferences: $e');
    }
  }
}
