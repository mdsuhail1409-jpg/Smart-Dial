import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// Thin wrapper around FlutterSecureStorage for JWT persistence.
///
/// The JWT is stored in the OS secure keystore (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
class SecureStorage {
  SecureStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Persist the JWT access token.
  static Future<void> saveToken(String token) =>
      _storage.write(key: AppConstants.jwtStorageKey, value: token);

  /// Retrieve the JWT access token, or null if not present.
  static Future<String?> getToken() =>
      _storage.read(key: AppConstants.jwtStorageKey);

  /// Remove the stored token (logout).
  static Future<void> deleteToken() =>
      _storage.delete(key: AppConstants.jwtStorageKey);
}
