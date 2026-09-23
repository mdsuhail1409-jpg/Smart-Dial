import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/constants/app_constants.dart';
import '../core/storage/secure_storage.dart';

/// Real-time WebSocket Coordination Service — Phase 7 & 8.
///
/// Maintains a persistent duplex connection to the backend coordination bus.
/// Listens for instantaneous events:
///   - RECIPROCAL_DETECTED: Both parties are calling simultaneously
///   - DECISION_RESOLVED: Server decision with action ('PROCEED', 'STANDBY', 'ASK_USER', 'BLOCK')
class WebSocketService {
  static final WebSocketService instance = WebSocketService._internal();
  WebSocketService._internal();

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  bool _isConnecting = false;

  final StreamController<Map<String, dynamic>> _reciprocalController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _decisionController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get reciprocalStream =>
      _reciprocalController.stream;
  Stream<Map<String, dynamic>> get decisionStream =>
      _decisionController.stream;

  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

  /// Connect to the coordination WebSocket using the stored JWT token.
  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;

    try {
      final token = await SecureStorage.getToken();
      if (token == null || token.isEmpty) {
        _isConnecting = false;
        return;
      }

      final url = '${AppConstants.wsUrl}?token=$token';
      _socket = await WebSocket.connect(url);
      _isConnecting = false;

      _startHeartbeat();

      _socket!.listen(
        _onMessage,
        onError: (err) => _onDisconnect(),
        onDone: () => _onDisconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _isConnecting = false;
      _onDisconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final event = data['event'];

      if (event == 'RECIPROCAL_DETECTED') {
        _reciprocalController.add(data);
      } else if (event == 'DECISION_RESOLVED') {
        _decisionController.add(data);
      }
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (isConnected) {
        _socket!.add(jsonEncode({'type': 'PING'}));
      }
    });
  }

  void _onDisconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket = null;
  }

  /// Close connection and clean up resources.
  void disconnect() {
    _onDisconnect();
  }

  void dispose() {
    disconnect();
    _reciprocalController.close();
    _decisionController.close();
  }
}
