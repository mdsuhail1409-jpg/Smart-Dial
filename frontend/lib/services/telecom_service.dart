import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// SmartDial Android Telecom bridge — Phase 4.
///
/// All voice audio travels via the SIM/cellular network.
/// WebRTC is NOT used.
///
/// MethodChannel: com.smartdial/telecom
/// EventChannel:  com.smartdial/call_events  (structured call events)
class TelecomService {
  TelecomService._();

  static const _methods = MethodChannel('com.smartdial/telecom');
  static const _events  = EventChannel('com.smartdial/call_events');

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Request CALL_PHONE permission. Returns true if granted.
  static Future<bool> requestCallPermission() async {
    final status = await Permission.phone.request();
    return status.isGranted;
  }

  static Future<bool> hasCallPermission() async => Permission.phone.isGranted;

  // ── Queries ───────────────────────────────────────────────────────────────

  static Future<bool> isTelecomSupported() async {
    try {
      return await _methods.invokeMethod<bool>('isTelecomSupported') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isDefaultDialer() async {
    try {
      return await _methods.invokeMethod<bool>('isDefaultDialer') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ── Role request ──────────────────────────────────────────────────────────

  /// Shows Android's official role-selection dialog. Never silently grants.
  /// Returns "requested" | "already_default" | "error: ..."
  static Future<String> requestDefaultDialerRole() async {
    try {
      return await _methods.invokeMethod<String>('requestDefaultDialerRole') ?? 'unknown';
    } on PlatformException catch (e) {
      return 'error: ${e.message}';
    }
  }

  // ── Cellular call placement ───────────────────────────────────────────────

  /// Place a real SIM/cellular call. Audio travels via carrier — not internet.
  /// Throws [TelecomException] on failure.
  static Future<bool> placeCellularCall(String phoneNumber) async {
    try {
      return await _methods.invokeMethod<bool>(
        'placeCellularCall', {'number': phoneNumber},
      ) ?? false;
    } on PlatformException catch (e) {
      throw TelecomException(e.message ?? 'Failed to place call');
    }
  }

  // ── Call controls ─────────────────────────────────────────────────────────

  /// End a specific call by its callId.
  /// Requires SmartDial to be the default phone app (InCallService must be bound).
  static Future<bool> endCall(String callId) async {
    try {
      return await _methods.invokeMethod<bool>('endCall', {'callId': callId}) ?? false;
    } on PlatformException catch (e) {
      throw TelecomException(e.message ?? 'Failed to end call');
    }
  }

  /// Answer an incoming call (Phase 4 foundation).
  /// Physical test requires a second phone — deferred for two-phone test.
  static Future<bool> answerCall(String callId) async {
    try {
      return await _methods.invokeMethod<bool>('answerCall', {'callId': callId}) ?? false;
    } on PlatformException catch (e) {
      throw TelecomException(e.message ?? 'Failed to answer call');
    }
  }

  /// Decline (reject) an incoming call.
  static Future<bool> declineCall(String callId) async {
    try {
      return await _methods.invokeMethod<bool>('declineCall', {'callId': callId}) ?? false;
    } on PlatformException catch (e) {
      throw TelecomException(e.message ?? 'Failed to decline call');
    }
  }

  // ── Active calls ──────────────────────────────────────────────────────────

  /// Returns a snapshot of currently tracked calls.
  static Future<List<ActiveCallInfo>> getActiveCalls() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>('getActiveCalls') ?? [];
      return raw
          .map((e) => ActiveCallInfo.fromMap(e as Map<Object?, Object?>))
          .toList();
    } on PlatformException {
      return [];
    }
  }

  // ── Phone accounts ────────────────────────────────────────────────────────

  static Future<List<PhoneAccountInfo>> getAvailablePhoneAccounts() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>('getAvailablePhoneAccounts') ?? [];
      return raw.map((e) => PhoneAccountInfo.fromMap(e as Map<Object?, Object?>)).toList();
    } on PlatformException {
      return [];
    }
  }

  // ── Call event stream ─────────────────────────────────────────────────────

  /// Structured call event stream from SmartDialInCallService.
  ///
  /// Each event is a [CallEvent] with:
  ///   event:     CALL_ADDED | STATE_CHANGED | CALL_REMOVED
  ///   callId:    stable identifier for this call
  ///   state:     CONNECTING | DIALING | RINGING | ACTIVE | HOLDING | DISCONNECTED
  ///   direction: OUTGOING | INCOMING | UNKNOWN
  ///
  /// Only received when SmartDial is the default phone app.
  static Stream<CallEvent> get callEventStream {
    return _events.receiveBroadcastStream().map((raw) {
      if (raw is Map) {
        return CallEvent.fromMap(Map<String, dynamic>.from(raw));
      }
      // Legacy string events (backwards compat)
      return CallEvent(
        event: 'STATE_CHANGED',
        callId: 'unknown',
        state: raw.toString(),
        direction: 'UNKNOWN',
      );
    });
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class CallEvent {
  final String event;      // CALL_ADDED | STATE_CHANGED | CALL_REMOVED
  final String callId;
  final String state;      // DIALING | RINGING | ACTIVE | HOLDING | DISCONNECTED
  final String direction;  // OUTGOING | INCOMING | UNKNOWN

  const CallEvent({
    required this.event,
    required this.callId,
    required this.state,
    required this.direction,
  });

  factory CallEvent.fromMap(Map<String, dynamic> m) => CallEvent(
    event:     m['event']?.toString()     ?? 'STATE_CHANGED',
    callId:    m['callId']?.toString()    ?? 'unknown',
    state:     m['state']?.toString()     ?? 'UNKNOWN',
    direction: m['direction']?.toString() ?? 'UNKNOWN',
  );

  bool get isActive      => state == 'ACTIVE';
  bool get isDialing     => state == 'DIALING' || state == 'CONNECTING';
  bool get isRinging     => state == 'RINGING';
  bool get isDisconnected => state == 'DISCONNECTED';
  bool get isOutgoing    => direction == 'OUTGOING';
  bool get isIncoming    => direction == 'INCOMING';

  @override
  String toString() => 'CallEvent($event callId=$callId state=$state dir=$direction)';
}

class ActiveCallInfo {
  final String callId;
  final String state;
  final String direction;

  const ActiveCallInfo({
    required this.callId,
    required this.state,
    required this.direction,
  });

  factory ActiveCallInfo.fromMap(Map<Object?, Object?> m) => ActiveCallInfo(
    callId:    m['callId']?.toString()    ?? '',
    state:     m['state']?.toString()     ?? 'UNKNOWN',
    direction: m['direction']?.toString() ?? 'UNKNOWN',
  );
}

class PhoneAccountInfo {
  final String id;
  final String label;
  final bool enabled;
  final int index;

  const PhoneAccountInfo({
    required this.id,
    required this.label,
    required this.enabled,
    required this.index,
  });

  factory PhoneAccountInfo.fromMap(Map<Object?, Object?> m) => PhoneAccountInfo(
    id:      m['id']?.toString()    ?? '',
    label:   m['label']?.toString() ?? 'SIM',
    enabled: m['enabled'] as bool?  ?? true,
    index:   m['index'] as int?     ?? 0,
  );
}

class TelecomException implements Exception {
  final String message;
  const TelecomException(this.message);
  @override
  String toString() => 'TelecomException: $message';
}
