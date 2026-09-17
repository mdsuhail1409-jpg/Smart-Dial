// Phase 4 unit tests — CallEvent and state mapping.
//
// These are MOCK TESTS — no Android device required.
// They verify the Dart-side data model, not physical Telecom behaviour.
//
// DEFERRED (second phone required):
//   - Real DIALING → ACTIVE transition
//   - Real RINGING → ACTIVE transition
//   - Real DISCONNECTED after hang-up
//   - Real incoming call from second phone

import 'package:flutter_test/flutter_test.dart';
import 'package:smartdial/services/telecom_service.dart';

void main() {
  group('CallEvent.fromMap — state mapping (MOCK TESTS)', () {
    test('DIALING state parsed correctly', () {
      final event = CallEvent.fromMap({
        'event': 'STATE_CHANGED',
        'callId': 'abc123',
        'state': 'DIALING',
        'direction': 'OUTGOING',
      });
      expect(event.state, 'DIALING');
      expect(event.isDialing, isTrue);
      expect(event.isActive, isFalse);
      expect(event.isOutgoing, isTrue);
    });

    test('RINGING state parsed correctly', () {
      final event = CallEvent.fromMap({
        'event': 'CALL_ADDED',
        'callId': 'abc456',
        'state': 'RINGING',
        'direction': 'INCOMING',
      });
      expect(event.state, 'RINGING');
      expect(event.isRinging, isTrue);
      expect(event.isIncoming, isTrue);
      expect(event.isOutgoing, isFalse);
    });

    test('ACTIVE state parsed correctly', () {
      final event = CallEvent.fromMap({
        'event': 'STATE_CHANGED',
        'callId': 'abc789',
        'state': 'ACTIVE',
        'direction': 'OUTGOING',
      });
      expect(event.state, 'ACTIVE');
      expect(event.isActive, isTrue);
      expect(event.isDisconnected, isFalse);
    });

    test('HOLDING state parsed correctly', () {
      final event = CallEvent.fromMap({
        'event': 'STATE_CHANGED',
        'callId': 'hold1',
        'state': 'HOLDING',
        'direction': 'OUTGOING',
      });
      expect(event.state, 'HOLDING');
      expect(event.isActive, isFalse);
      expect(event.isDisconnected, isFalse);
    });

    test('DISCONNECTED state parsed correctly', () {
      final event = CallEvent.fromMap({
        'event': 'CALL_REMOVED',
        'callId': 'done1',
        'state': 'DISCONNECTED',
        'direction': 'OUTGOING',
      });
      expect(event.state, 'DISCONNECTED');
      expect(event.isDisconnected, isTrue);
      expect(event.isActive, isFalse);
    });

    test('CONNECTING state parsed correctly', () {
      final event = CallEvent.fromMap({
        'event': 'STATE_CHANGED',
        'callId': 'conn1',
        'state': 'CONNECTING',
        'direction': 'OUTGOING',
      });
      expect(event.state, 'CONNECTING');
      expect(event.isDialing, isTrue); // CONNECTING treated as dialing
    });

    test('Unknown state does not crash', () {
      final event = CallEvent.fromMap({
        'event': 'STATE_CHANGED',
        'callId': 'unk1',
        'state': 'UNKNOWN(99)',
        'direction': 'UNKNOWN',
      });
      expect(event.state, 'UNKNOWN(99)');
      expect(event.isActive, isFalse);
      expect(event.isDisconnected, isFalse);
    });

    test('Missing fields use safe defaults', () {
      final event = CallEvent.fromMap({});
      expect(event.callId, 'unknown');
      expect(event.direction, 'UNKNOWN');
      expect(event.state, 'UNKNOWN');
    });

    test('CALL_ADDED event type parsed', () {
      final event = CallEvent.fromMap({
        'event': 'CALL_ADDED',
        'callId': 'new1',
        'state': 'DIALING',
        'direction': 'OUTGOING',
      });
      expect(event.event, 'CALL_ADDED');
    });

    test('CALL_REMOVED event type parsed', () {
      final event = CallEvent.fromMap({
        'event': 'CALL_REMOVED',
        'callId': 'rem1',
        'state': 'DISCONNECTED',
        'direction': 'INCOMING',
      });
      expect(event.event, 'CALL_REMOVED');
      expect(event.isIncoming, isTrue);
    });

    test('toString does not throw', () {
      final event = CallEvent.fromMap({
        'event': 'STATE_CHANGED',
        'callId': 'str1',
        'state': 'ACTIVE',
        'direction': 'OUTGOING',
      });
      expect(event.toString(), contains('ACTIVE'));
    });
  });

  group('ActiveCallInfo.fromMap (MOCK TESTS)', () {
    test('parses correctly', () {
      final info = ActiveCallInfo.fromMap({
        'callId': 'x1',
        'state': 'ACTIVE',
        'direction': 'OUTGOING',
      });
      expect(info.callId, 'x1');
      expect(info.state, 'ACTIVE');
      expect(info.direction, 'OUTGOING');
    });

    test('safe defaults on empty map', () {
      final info = ActiveCallInfo.fromMap({});
      expect(info.callId, '');
      expect(info.state, 'UNKNOWN');
      expect(info.direction, 'UNKNOWN');
    });
  });

  group('PhoneAccountInfo.fromMap (MOCK TESTS)', () {
    test('parses correctly', () {
      final acc = PhoneAccountInfo.fromMap({
        'id': 'sim1',
        'label': 'Jio',
        'enabled': true,
        'index': 0,
      });
      expect(acc.id, 'sim1');
      expect(acc.label, 'Jio');
      expect(acc.enabled, isTrue);
      expect(acc.index, 0);
    });

    test('safe defaults on empty map', () {
      final acc = PhoneAccountInfo.fromMap({});
      expect(acc.id, '');
      expect(acc.label, 'SIM');
      expect(acc.enabled, isTrue);
    });
  });
}
