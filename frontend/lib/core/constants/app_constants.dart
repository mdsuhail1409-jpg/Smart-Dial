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
    defaultValue: 'https://smart-dial.onrender.com', // Live Render Cloud Backend
  );

  // JWT storage key
  static const String jwtStorageKey = 'smartdial_jwt';

  /// WebSocket endpoint derived from baseUrl
  static String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portStr = (uri.hasPort && uri.port != 80 && uri.port != 443) ? ':${uri.port}' : '';
    return '$wsScheme://${uri.host}$portStr/ws/calls';
  }

  // App name
  static const String appName = 'SmartDial';
}
