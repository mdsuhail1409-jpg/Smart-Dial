import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/telecom_service.dart';

/// InCall Screen — Phase 4
///
/// Shown when an active Telecom call is in progress.
///
/// Handles:
///  - Outgoing calls (DIALING → ACTIVE → DISCONNECTED)
///  - Incoming calls (RINGING → ACTIVE → DISCONNECTED) [foundation]
///  - Call duration timer (starts when ACTIVE)
///  - End call button (via TelecomService.endCall)
///  - Answer / Decline buttons for incoming calls
///
/// Physical incoming-call test: DEFERRED — second phone required.
/// Voice audio: SIM/cellular network — NOT internet, NOT WebRTC.
class InCallScreen extends StatefulWidget {
  final String callId;
  final String contactName;
  final String phoneNumber;
  final String initialState;   // DIALING | RINGING | ACTIVE
  final String direction;      // OUTGOING | INCOMING | UNKNOWN

  const InCallScreen({
    super.key,
    required this.callId,
    required this.contactName,
    required this.phoneNumber,
    required this.initialState,
    required this.direction,
  });

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  late String _state;
  late String _direction;

  // Call duration
  int _durationSeconds = 0;
  Timer? _durationTimer;
  StreamSubscription<CallEvent>? _eventSub;

  bool _isEndingCall   = false;
  bool _isAnswering    = false;
  bool _isDeclining    = false;

  @override
  void initState() {
    super.initState();
    _state     = widget.initialState;
    _direction = widget.direction;
    _subscribeEvents();
    if (_state == 'ACTIVE') _startTimer();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  void _subscribeEvents() {
    _eventSub = TelecomService.callEventStream.listen(
      (event) {
        // Only handle events for this call
        if (event.callId != widget.callId) return;
        if (!mounted) return;

        setState(() {
          _state     = event.state;
          _direction = event.direction != 'UNKNOWN' ? event.direction : _direction;
        });

        if (event.isActive && _durationTimer == null) _startTimer();

        if (event.isDisconnected) {
          _durationTimer?.cancel();
          // Auto-pop after brief delay to show DISCONNECTED state
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
      onError: (_) {},
    );
  }

  void _startTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  String get _formattedDuration {
    final m = _durationSeconds ~/ 60;
    final s = _durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Call controls ─────────────────────────────────────────────────────────

  Future<void> _endCall() async {
    setState(() => _isEndingCall = true);
    try {
      await TelecomService.endCall(widget.callId);
    } on TelecomException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('End call failed: ${e.message}'), backgroundColor: Colors.red),
      );
      setState(() => _isEndingCall = false);
    }
  }

  Future<void> _answerCall() async {
    setState(() => _isAnswering = true);
    try {
      await TelecomService.answerCall(widget.callId);
      if (mounted) setState(() => _isAnswering = false);
    } on TelecomException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Answer failed: ${e.message}'), backgroundColor: Colors.red),
      );
      setState(() => _isAnswering = false);
    }
  }

  Future<void> _declineCall() async {
    setState(() => _isDeclining = true);
    try {
      await TelecomService.declineCall(widget.callId);
      if (mounted) setState(() => _isDeclining = false);
    } on TelecomException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Decline failed: ${e.message}'), backgroundColor: Colors.red),
      );
      setState(() => _isDeclining = false);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  Color get _bgColor => switch (_state) {
    'ACTIVE'       => Colors.green.shade800,
    'DIALING'      => Colors.blue.shade800,
    'CONNECTING'   => Colors.blue.shade700,
    'RINGING'      => Colors.indigo.shade800,
    'HOLDING'      => Colors.orange.shade800,
    'DISCONNECTED' => Colors.grey.shade800,
    _              => Colors.blueGrey.shade800,
  };

  String get _stateLabel => switch (_state) {
    'ACTIVE'       => _direction == 'INCOMING' ? 'In Call' : 'Connected',
    'DIALING'      => 'Dialling…',
    'CONNECTING'   => 'Connecting…',
    'RINGING'      => 'Incoming Call',
    'HOLDING'      => 'On Hold',
    'DISCONNECTED' => 'Call Ended',
    _              => _state,
  };

  @override
  Widget build(BuildContext context) {
    final isRinging      = _state == 'RINGING' && _direction == 'INCOMING';
    final isActive       = _state == 'ACTIVE';
    final isDisconnected = _state == 'DISCONNECTED';

    return PopScope(
      canPop: isDisconnected,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),

              // ── Contact avatar ────────────────────────────────────────────
              CircleAvatar(
                radius: 52,
                backgroundColor: Colors.white24,
                child: Text(
                  widget.contactName.isNotEmpty
                      ? widget.contactName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 42, color: Colors.white, fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Contact name ──────────────────────────────────────────────
              Text(
                widget.contactName,
                style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),

              // ── Phone number ──────────────────────────────────────────────
              Text(
                widget.phoneNumber,
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
              const SizedBox(height: 12),

              // ── State label ───────────────────────────────────────────────
              Text(
                _stateLabel,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),

              // ── Duration (only when active) ───────────────────────────────
              if (isActive)
                Text(
                  _formattedDuration,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),

              // ── Direction badge ───────────────────────────────────────────
              if (!isDisconnected && _direction != 'UNKNOWN')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _direction == 'OUTGOING' ? '↑ Outgoing' : '↓ Incoming',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),

              const Spacer(),

              // ── Call controls ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 48, left: 40, right: 40),
                child: isRinging
                    ? _IncomingControls(
                        isAnswering: _isAnswering,
                        isDeclining: _isDeclining,
                        onAnswer:  _answerCall,
                        onDecline: _declineCall,
                      )
                    : isDisconnected
                        ? TextButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white70),
                            label: const Text('Dismiss',
                                style: TextStyle(color: Colors.white70, fontSize: 16)),
                          )
                        : _EndCallButton(
                            isEnding: _isEndingCall,
                            onEnd: _endCall,
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EndCallButton extends StatelessWidget {
  final bool isEnding;
  final VoidCallback onEnd;

  const _EndCallButton({required this.isEnding, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: isEnding ? null : onEnd,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.red.shade900, blurRadius: 12)],
          ),
          child: isEnding
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : const Icon(Icons.call_end, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

class _IncomingControls extends StatelessWidget {
  final bool isAnswering;
  final bool isDeclining;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const _IncomingControls({
    required this.isAnswering,
    required this.isDeclining,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Decline
        Column(
          children: [
            GestureDetector(
              onTap: isDeclining ? null : onDecline,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  shape: BoxShape.circle,
                ),
                child: isDeclining
                    ? const Center(
                        child: SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : const Icon(Icons.call_end, color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),

        // Answer
        Column(
          children: [
            GestureDetector(
              onTap: isAnswering ? null : onAnswer,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  shape: BoxShape.circle,
                ),
                child: isAnswering
                    ? const Center(
                        child: SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : const Icon(Icons.call, color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Answer', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
