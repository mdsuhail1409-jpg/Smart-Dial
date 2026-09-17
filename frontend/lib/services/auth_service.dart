import '../core/api/api_client.dart';
import '../core/storage/secure_storage.dart';

/// High-level authentication service.
///
/// Wraps [ApiClient] calls and manages JWT storage.
/// UI layers should call this instead of ApiClient directly.
class AuthService {
  AuthService._();

  /// Register a new user.
  ///
  /// Returns null on success, or an error message on failure.
  static Future<String?> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final result = await ApiClient.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
    if (result.isSuccess) return null;
    return result.error;
  }

  /// Log in and securely store the JWT.
  ///
  /// Returns null on success, or an error message on failure.
  static Future<String?> login({
    required String email,
    required String password,
  }) async {
    final result = await ApiClient.login(email: email, password: password);
    if (!result.isSuccess) return result.error;

    final token = result.data!['access_token'] as String?;
    if (token == null) return 'Server did not return a token';

    await SecureStorage.saveToken(token);
    return null; // success
  }

  /// Remove the stored JWT (logout).
  static Future<void> logout() => SecureStorage.deleteToken();

  /// Check whether a JWT is currently stored.
  static Future<bool> isLoggedIn() async {
    final token = await SecureStorage.getToken();
    return token != null;
  }
}
