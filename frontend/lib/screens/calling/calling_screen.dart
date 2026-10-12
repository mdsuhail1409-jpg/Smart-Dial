import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_theme.dart';
import '../../core/models/call_request.dart';
import '../../core/models/user.dart';
import '../../core/widgets/smart_widgets.dart';
import '../../services/call_service.dart';
import '../../services/telecom_service.dart';
import '../../services/websocket_service.dart';
import '../incall/incall_screen.dart';

/// Calling Screen — Matches Figma Screens 6A, 6B, 7A, and 7B
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
  String _simCallState = '';
  bool _simCallStarted = false;
  bool _isPlacingCall = false;
  bool _isCancelling = false;
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

    // Auto-trigger cellular SIM call after 1s if no reciprocal conflict
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_simCallStarted && !_isPlacingCall && _decisionAction != 'STANDBY') {
        _placeSimCall();
      }
    });
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
      final reason = event['reason'] as String?;
      final pairId = event['pair_id'] as String?;

      if (action != null) {
        setState(() {
          _decisionAction = action;
          _decisionReason = reason;
        });

        if (action == 'PROCEED') {
          _showDecisionModal(isProceed: true);
          if (!_simCallStarted && !_isPlacingCall) {
            _placeSimCall();
          }
        } else if (action == 'STANDBY') {
          _showDecisionModal(isProceed: false);
        } else if (action == 'ASK_USER' && pairId != null) {
          _showAskUserSheet(pairId);
        } else if (action == 'BLOCK') {
          _cancelCloudRequest();
        }
      }
    });
  }

  void _showDecisionModal({required bool isProceed}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF131D33),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Dual Phones Synchronizing graphic (Figma 7A & 7B)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPhoneIcon(isProceed ? AppColors.green : AppColors.cyan),
                  const SizedBox(width: 14),
                  Icon(
                    Icons.sync_alt,
                    size: 24,
                    color: isProceed ? AppColors.green : AppColors.cyan,
                  ),
                  const SizedBox(width: 14),
                  _buildPhoneIcon(isProceed ? AppColors.green : AppColors.cyan),
                ],
              ),
              const SizedBox(height: 20),

              const Text(
                'Simultaneous Call Detected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // Action Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (isProceed ? AppColors.green : AppColors.cyan)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isProceed ? AppColors.green : AppColors.cyan,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isProceed ? Icons.check_circle : Icons.phone_callback,
                      size: 14,
                      color: isProceed ? AppColors.green : AppColors.cyan,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isProceed ? 'ACTION: PROCEED' : 'ACTION: STANDBY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isProceed ? AppColors.green : AppColors.cyan,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                isProceed
                    ? "SmartDial executed the fastest call: Your call to ${widget.receiver.name} was initiated first and is connecting now."
                    : "The person you are trying to call is already calling you.\n\nYour outgoing call is on hold—please answer ${widget.receiver.name}'s incoming call!",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isProceed ? AppColors.green : AppColors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Got it / Continue',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhoneIcon(Color color) {
    return Container(
      width: 32,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  void _showAskUserSheet(String pairId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF131D33),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Call Collision Detected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Both you and ${widget.receiver.name} called at the exact same moment. Who should place the cellular call?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ApiClient.respondToDecision(pairId: pairId, action: 'ALLOW_A_TO_B');
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
              child: const Text('I will place the call'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ApiClient.respondToDecision(pairId: pairId, action: 'ALLOW_B_TO_A');
              },
              child: const Text('Let them call me (Standby)'),
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
          _simCallState = event.state;
          _simCallStarted = true;
          if (_activeCallId == null && event.event == 'CALL_ADDED') {
            _activeCallId = event.callId;
          }
        });

        if ((event.event == 'CALL_ADDED' || event.isActive) && _activeCallId != null) {
          _navigateToInCall(event);
        }
      },
    );
  }

  void _navigateToInCall(CallEvent event) {
    _eventSub?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => InCallScreen(
          callId: event.callId,
          contactName: widget.receiver.name,
          phoneNumber: widget.receiver.phone,
          initialState: event.state,
          direction: event.direction,
        ),
      ),
    );
  }

  Future<void> _cancelCloudRequest() async {
    setState(() => _isCancelling = true);
    try {
      final updated = await CallService.cancelCallRequest(_request.requestId);
      if (!mounted) return;
      setState(() {
        _request = updated;
        _isCancelling = false;
      });
      Navigator.pop(context);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _placeSimCall() async {
    setState(() => _isPlacingCall = true);
    try {
      await TelecomService.placeCellularCall(widget.receiver.phone);
    } catch (_) {}
    if (mounted) setState(() => _isPlacingCall = false);
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'SD';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isReciprocal = _request.reciprocalFlag || _decisionAction != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Header: SmartDial Telecom Routing (Figma 6A & 6B)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cell_tower, color: AppColors.cyan, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'SmartDial Telecom Routing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
                SizedBox(width: 4),
                Text(
                  'Encrypted intent • Cellular audio',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),

            const Spacer(flex: 1),

            // Center Radar Animation with Contact Avatar
            RadarPulseWidget(
              size: 260,
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF2C3E66), Color(0xFF1E283F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    _getInitials(widget.receiver.name),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              widget.receiver.name,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.receiver.phone,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),

            const Spacer(flex: 1),

            // Conditional Status Card: Normal vs Reciprocal Collision
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: isReciprocal
                  // Reciprocal Detected Card (Figma 6B)
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF381B47), Color(0xFF221634)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF8B5CF6), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.bolt, color: AppColors.amber, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'RECIPROCAL CALL DETECTED',
                                style: TextStyle(
                                  color: AppColors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _decisionAction == 'STANDBY'
                                ? 'The person you are trying to call is already calling you'
                                : (_decisionReason ??
                                    'Both users dialed within window • Connecting fastest call...'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _decisionAction == 'STANDBY' ? FontWeight.w600 : FontWeight.normal,
                              color: _decisionAction == 'STANDBY' ? AppColors.cyan : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  // Normal Routing Card (Figma 6A)
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.cyan.withValues(alpha: 0.15),
                            ),
                            child: const Icon(Icons.radio_button_checked,
                                size: 16, color: AppColors.cyan),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'LIVE INTENT REGISTRY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.cyan,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _simCallState.isNotEmpty
                                      ? 'SIM State: $_simCallState'
                                      : 'Registering Intent ${_request.requestId}... Placing SIM call...',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            const Spacer(flex: 1),

            // Big Red Call End Button
            GestureDetector(
              onTap: _isCancelling ? null : _cancelCloudRequest,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.redGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cancel / End Attempt',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
