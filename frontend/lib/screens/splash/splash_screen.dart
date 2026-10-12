import 'package:flutter/material.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widgets/smart_widgets.dart';
import '../../services/auth_service.dart';

/// Splash screen shown on launch.
/// Matches Figma Screen 1: Radar scanner, Hexagon Infinity Logo, v0.3.0 Engine.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // 800ms delay so splash is visible and timer completes cleanly
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, loggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Radar pulse with glowing hexagon logo
            Center(
              child: RadarPulseWidget(
                size: 260,
                child: const SmartDialHexagonLogo(size: 88),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'SmartDial',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Intelligent Cellular & Collision-Free Calling',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            // Bottom 3 dots & status indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDot(0.4),
                const SizedBox(width: 6),
                _buildDot(1.0),
                const SizedBox(width: 6),
                _buildDot(0.4),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Initializing telecom registry & SIM binding...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'v0.3.0 Engine',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(double opacity) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
