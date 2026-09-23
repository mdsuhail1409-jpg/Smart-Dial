import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/models/call_request.dart';
import '../../core/models/user.dart';
import '../../services/call_service.dart';
import '../../services/telecom_service.dart';
import '../../services/websocket_service.dart';
import '../incall/incall_screen.dart';

/// Calling Screen — Phase 4-8
///
/// Shown after User A presses CALL on User B.
///
/// Flow:
///  1. Cloud call intent (CR_...) already created — passed in as [initialRequest].
///  2. Real-time WebSocket connects to SmartDial coordination bus.
///  3. If reciprocal calling detected: receives DECISION_RESOLVED event.
///     - PROCEED: Gated SIM call automatically placed/continued.
///     - STANDBY: Outgoing attempt aborted; waits for incoming carrier call.
///     - ASK_USER: Presents choice dialog.
///     - BLOCK: Aborts call immediately.
///
/// Voice audio path: SIM / cellular — NOT internet, NOT WebRTC.
class CallingScreen extends StatefulWidget {
  final CallRequest initialRequest;
  final User receiver;

  const CallingScreen({
    super.key,
    required this.initialRequest,
    required this.receiver,
  });

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen> {
  late CallRequest _request;
  String _simCallState  = '';
  bool _simCallStarted  = false;
  bool _isPlacingCall   = false;
  bool _isCancelling    = false;
  String? _activeCallId;

  String? _decisionAction;
  String? _decisionReason;

  StreamSubscription<CallEvent>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _reciprocalWsSub;
  StreamSubscription<Map<String, dynamic>>? _decisionWsSub;

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest;
    _subscribeCallEvents();
    _subscribeWebSocketEvents();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _reciprocalWsSub?.cancel();
    _decisionWsSub?.cancel();
    super.dispose();
  }

  void _subscribeWebSocketEvents() {
    WebSocketService.instance.connect();

    _reciprocalWsSub = WebSocketService.instance.reciprocalStream.listen((event) {
      if (!mounted) return;
      final pairId = event['pair_id'] as String?;
      if (pairId != null) {
        setState(() {
          _request = _request.copyWith(
            reciprocalFlag: true,
            pairId: pairId,
          );
        });
      }
    });

    _decisionWsSub = WebSocketService.instance.decisionStream.listen((event) {
      if (!mounted) return;
      final action = event['action'] as String?;
      final pairId = event['pair_id'] as String?;
      final reason = event['reason_code'] as String?;

      if (action != null) {
        setState(() {
          _decisionAction = action;
          _decisionReason = reason;
        });
        _handleDecisionAction(action, pairId ?? _request.pairId ?? '');
      }
    });
  }

  void _handleDecisionAction(String action, String pairId) {
    if (action == 'PROCEED') {
      if (!_simCallStarted && !_isPlacingCall) {
        _placeSIMCall();
      }
    } else if (action == 'STANDBY') {
      if (_activeCallId != null) {
        TelecomService.endCall(_activeCallId!);
      }
    } else if (action == 'BLOCK') {
      if (_activeCallId != null) {
        TelecomService.endCall(_activeCallId!);
      }
      _cancelCloudRequest();
    } else if (action == 'ASK_USER') {
      _showAskUserModal(pairId);
    }
  }

  void _showAskUserModal(String pairId) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.compare_arrows, color: Colors.purple, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Simultaneous Call Detected',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Both of you are calling each other right now. Who should place the cellular call?',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                ApiClient.respondToDecision(pairId: pairId, action: 'ALLOW_A_TO_B');
              },
              icon: const Icon(Icons.call_made),
              label: const Text('I will place the call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                ApiClient.respondToDecision(pairId: pairId, action: 'ALLOW_B_TO_A');
              },
              icon: const Icon(Icons.call_received),
              label: const Text('Let them call me (Standby)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ApiClient.respondToDecision(pairId: pairId, action: 'BLOCK');
              },
              child: Text('Cancel Both Calls', style: TextStyle(color: Colors.red.shade700)),
            ),
          ],
        ),
      ),
    );
  }

  void _subscribeCallEvents() {
    _eventSub = TelecomService.callEventStream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _simCallState  = event.state;
          _simCallStarted = true;
          if (_activeCallId == null && event.event == 'CALL_ADDED') {
            _activeCallId = event.callId;
          }
        });

        // Auto-navigate to InCallScreen once the call is added or active
        if ((event.event == 'CALL_ADDED' || event.isActive) && _activeCallId != null) {
          _navigateToInCall(event);
        }
      },
      onError: (_) {},
    );
  }

  void _navigateToInCall(CallEvent event) {
    // Navigate once — prevent duplicate navigation
    _eventSub?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => InCallScreen(
          callId:       event.callId,
          contactName:  widget.receiver.name,
          phoneNumber:  widget.receiver.phone,
          initialState: event.state,
          direction:    event.direction,
        ),
      ),
    );
  }

  // ── Cancel cloud request ──────────────────────────────────────────────────

  Future<void> _cancelCloudRequest() async {
    setState(() => _isCancelling = true);
    try {
      final updated = await CallService.cancelCallRequest(_request.requestId);
      if (!mounted) return;
      setState(() {
        _request = updated;
        _isCancelling = false;
      });
    } on CallServiceException catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
      );
    }
  }

  // ── Place SIM call ────────────────────────────────────────────────────────

  Future<void> _placeSIMCall() async {
    final phone = widget.receiver.phone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number registered for this user.'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isPlacingCall = true);

    final granted = await TelecomService.requestCallPermission();
    if (!mounted) return;

    if (!granted) {
      setState(() => _isPlacingCall = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Phone call permission is required.\n'
            'Please grant it in Settings → App permissions.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    try {
      await TelecomService.placeCellularCall(phone);
      if (!mounted) return;
      setState(() {
        _isPlacingCall  = false;
        _simCallStarted = true;
        _simCallState   = 'DIALING';
      });
    } on TelecomException catch (e) {
      if (!mounted) return;
      setState(() => _isPlacingCall = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SIM call failed: ${e.message}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color get _statusColor => switch (_simCallState) {
    'DIALING'    => Colors.blue.shade600,
    'CONNECTING' => Colors.blue.shade500,
    'ACTIVE'     => Colors.green.shade700,
    'RINGING'    => Colors.indigo.shade600,
    _            => Colors.grey.shade500,
  };

  Color get _cloudStatusColor => switch (_request.status) {
    'PENDING'   => Colors.blue.shade700,
    'CANCELLED' => Colors.orange.shade700,
    'EXPIRED'   => Colors.grey.shade600,
    _           => Colors.grey.shade600,
  };

  @override
  Widget build(BuildContext context) {
    final isPending  = _request.isPending;
    final isTerminal = !isPending;

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: const Text('SmartDial'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Receiver avatar
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: Colors.blue.shade100,
                child: Text(
                  widget.receiver.name.isNotEmpty
                      ? widget.receiver.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(child: Text(widget.receiver.name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            Center(child: Text(widget.receiver.phone,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600))),
            const SizedBox(height: 24),

            // Cloud intent card
            _InfoCard(title: 'Cloud Intent', children: [
              _InfoRow('Request ID', _request.requestId,
                  mono: true, color: Colors.blue.shade800),
              _InfoRow('Status', _request.status, color: _cloudStatusColor),
              _InfoRow('Expires',
                  _request.expiresAt.toLocal().toString().substring(11, 19)),
            ]),
            const SizedBox(height: 12),

            // Reciprocal detection badge — Phase 5
            if (_request.reciprocalFlag && _request.pairId != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sync, color: Colors.purple.shade700, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'RECIPROCAL CALL DETECTED',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade800,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _InfoRow('Pair', _request.pairId!,
                        mono: true, color: Colors.purple.shade700),
                  ],
                ),
              ),

            // Reciprocal Decision Status
            if (_decisionAction != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _decisionAction == 'PROCEED'
                      ? Colors.green.shade50
                      : (_decisionAction == 'STANDBY'
                          ? Colors.orange.shade50
                          : Colors.purple.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _decisionAction == 'PROCEED'
                        ? Colors.green.shade400
                        : (_decisionAction == 'STANDBY'
                            ? Colors.orange.shade400
                            : Colors.purple.shade400),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _decisionAction == 'PROCEED'
                              ? Icons.check_circle
                              : (_decisionAction == 'STANDBY'
                                  ? Icons.phone_callback
                                  : Icons.info_outline),
                          color: _decisionAction == 'PROCEED'
                              ? Colors.green.shade700
                              : (_decisionAction == 'STANDBY'
                                  ? Colors.orange.shade800
                                  : Colors.purple.shade700),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'DECISION: $_decisionAction',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _decisionAction == 'PROCEED'
                                ? Colors.green.shade900
                                : (_decisionAction == 'STANDBY'
                                    ? Colors.orange.shade900
                                    : Colors.purple.shade900),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _decisionAction == 'PROCEED'
                          ? 'SmartDial elected your phone to place the cellular call.'
                          : (_decisionAction == 'STANDBY'
                              ? 'The other party was elected to dial. Standing by to receive.'
                              : 'Policy reason: $_decisionReason'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // SIM call state
            if (_simCallState.isNotEmpty)
              _InfoCard(title: 'SIM / Cellular Call', children: [
                _InfoRow('State', _simCallState, color: _statusColor),
                const _InfoRow('Path', 'Android Telecom → SIM → Carrier'),
                const _InfoRow('Audio', 'Cellular network (not internet)'),
              ]),
            const SizedBox(height: 20),

            // Place SIM Call button
            if (isPending && !_simCallStarted)
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isPlacingCall ? null : _placeSIMCall,
                  icon: _isPlacingCall
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.call),
                  label: Text(_isPlacingCall ? 'Connecting…' : 'Place SIM Call',
                      style: const TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

            // Waiting for InCallService (after call placed, before event arrives)
            if (isPending && _simCallStarted && _activeCallId == null)
              Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text('Waiting for call state…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text('(Full in-call controls appear when InCallService is active)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ]),

            const SizedBox(height: 16),

            // Cancel cloud request
            if (isPending)
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isCancelling ? null : _cancelCloudRequest,
                  icon: _isCancelling
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.close),
                  label: const Text('CANCEL REQUEST', style: TextStyle(fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade400),
                  ),
                ),
              ),

            // Terminal state
            if (isTerminal) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Request ${_request.status}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Back to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: TextStyle(fontSize: 10,
            fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool mono;
  const _InfoRow(this.label, this.value, {this.color, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 90,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: color,
            fontFamily: mono ? 'monospace' : null))),
      ]),
    );
  }
}
