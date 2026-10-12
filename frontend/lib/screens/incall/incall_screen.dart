import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widgets/smart_widgets.dart';
import '../../services/telecom_service.dart';

/// InCall Screen — Matches Figma Screen 8 (Active In-Call HUD)
class InCallScreen extends StatefulWidget {
  final String callId;
  final String contactName;
  final String phoneNumber;
  final String initialState; // DIALING | RINGING | ACTIVE
  final String direction; // OUTGOING | INCOMING | UNKNOWN

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

  // In-call toggles
  bool _isMuted = false;
  bool _isSpeaker = true; // Set to true by default matching Figma Screen 8
  bool _isOnHold = false;
  bool _isBluetooth = false;

  bool _isEndingCall = false;
  bool _isAnswering = false;
  bool _isDeclining = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _direction = widget.direction;
    _subscribeEvents();
    if (_state == 'ACTIVE' || _state == 'DIALING') _startTimer();
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
        if (event.callId != widget.callId) return;
        if (!mounted) return;

        setState(() {
          _state = event.state;
          _direction =
              event.direction != 'UNKNOWN' ? event.direction : _direction;
        });

        if (event.isActive && _durationTimer == null) _startTimer();

        if (event.isDisconnected) {
          _durationTimer?.cancel();
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
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

  Future<void> _endCall() async {
    setState(() => _isEndingCall = true);
    try {
      await TelecomService.endCall(widget.callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _answerCall() async {
    setState(() => _isAnswering = true);
    try {
      await TelecomService.answerCall(widget.callId);
    } catch (_) {}
    if (mounted) setState(() => _isAnswering = false);
  }

  Future<void> _declineCall() async {
    setState(() => _isDeclining = true);
    try {
      await TelecomService.declineCall(widget.callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'SD';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  void _showKeypadModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131D33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('In-Call Keypad (DTMF)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#']
                  .map((d) => InkWell(
                        onTap: () {},
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Center(
                            child: Text(
                              d,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRinging = _state == 'RINGING' && _direction == 'INCOMING';
    final isDisconnected = _state == 'DISCONNECTED';

    return PopScope(
      canPop: isDisconnected,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Top Carrier Pill (Figma Screen 8)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.circle, size: 8, color: AppColors.green),
                    SizedBox(width: 6),
                    Text(
                      'HD Voice • SIM 1 (Jio 5G)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isDisconnected
                    ? 'Call Ended'
                    : (isRinging ? 'Incoming Cellular Call' : 'Active SIM Cellular Call'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),

              const Spacer(flex: 1),

              // Audio Gauge Avatar
              AudioGaugeAvatar(
                initials: _getInitials(widget.contactName),
                size: 110,
              ),
              const SizedBox(height: 24),

              // Caller Name
              Text(
                widget.contactName,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // Call Duration
              Text(
                _formattedDuration,
                style: const TextStyle(
                  fontSize: 20,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),

              const Spacer(flex: 1),

              // If Incoming Ringing Call
              if (isRinging)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      GestureDetector(
                        onTap: _isDeclining ? null : _declineCall,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.red,
                          ),
                          child: const Icon(Icons.call_end, color: Colors.white, size: 30),
                        ),
                      ),
                      GestureDetector(
                        onTap: _isAnswering ? null : _answerCall,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.green,
                          ),
                          child: const Icon(Icons.call, color: Colors.white, size: 30),
                        ),
                      ),
                    ],
                  ),
                )
              else
                // 2x3 In-Call Action Grid (Figma Screen 8)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildGridButton(
                            icon: _isMuted ? Icons.mic_off : Icons.mic_none,
                            label: 'Mute',
                            isActive: _isMuted,
                            onTap: () => setState(() => _isMuted = !_isMuted),
                          ),
                          _buildGridButton(
                            icon: Icons.dialpad,
                            label: 'Keypad',
                            isActive: false,
                            onTap: _showKeypadModal,
                          ),
                          _buildGridButton(
                            icon: Icons.volume_up,
                            label: 'Speaker',
                            isActive: _isSpeaker,
                            onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildGridButton(
                            icon: Icons.person_add_alt_1_outlined,
                            label: 'Add Call',
                            isActive: false,
                            onTap: () {},
                          ),
                          _buildGridButton(
                            icon: _isOnHold ? Icons.play_arrow : Icons.pause,
                            label: 'Hold',
                            isActive: _isOnHold,
                            onTap: () => setState(() => _isOnHold = !_isOnHold),
                          ),
                          _buildGridButton(
                            icon: Icons.bluetooth,
                            label: 'Bluetooth /\nAudio Route',
                            isActive: _isBluetooth,
                            onTap: () => setState(() => _isBluetooth = !_isBluetooth),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const Spacer(flex: 1),

              // Wide Red Pill End Call Button (Figma Screen 8)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.red.withValues(alpha: 0.5),
                    ),
                    onPressed: _isEndingCall ? null : _endCall,
                    child: _isEndingCall
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.call_end, size: 24),
                              SizedBox(width: 10),
                              Text(
                                'End Call',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? AppColors.cyan.withValues(alpha: 0.15)
                  : const Color(0xFF131D33),
              border: Border.all(
                color: isActive ? AppColors.cyan : AppColors.border,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: 24,
              color: isActive ? AppColors.cyan : Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: isActive ? AppColors.cyan : AppColors.textSecondary,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
