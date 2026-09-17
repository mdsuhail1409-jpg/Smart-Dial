/// Centralised configuration constants for SmartDial.
///
/// Switch [baseUrl] between environments here — never hardcode it
/// in individual service files.
///
/// Android emulator reaches the host machine at 10.0.2.2.
/// Physical device: use your machine's LAN IP, e.g. http://192.168.1.x:8000
/// Production: replace with your deployed API URL.
class AppConstants {
  AppConstants._(); // prevent instantiation

  /// Change this one value to target a different backend.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000', // ADB reverse USB -> host machine
  );

  // JWT storage key
  static const String jwtStorageKey = 'smartdial_jwt';

  // App name
  static const String appName = 'SmartDial';
}
