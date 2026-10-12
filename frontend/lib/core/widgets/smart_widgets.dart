import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

/// Hexagonal glowing logo with infinity symbol inside — matching Figma screen 1 & 2
class SmartDialHexagonLogo extends StatelessWidget {
  final double size;
  const SmartDialHexagonLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _HexagonPainter(),
          ),
          CustomPaint(
            size: Size(size * 0.5, size * 0.5),
            painter: _InfinityPainter(),
          ),
        ],
      ),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - (math.pi / 6);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Fill background
    final bgPaint = Paint()
      ..color = const Color(0xFF142036)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bgPaint);

    // Neon Cyan / Indigo border stroke
    final strokePaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.cyan, AppColors.primary, AppColors.cyanGlow],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfinityPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    // Smooth lemniscate / infinity curve
    path.moveTo(w * 0.5, h * 0.5);
    path.cubicTo(w * 0.25, 0, 0, h * 0.2, 0, h * 0.5);
    path.cubicTo(0, h * 0.8, w * 0.25, h, w * 0.5, h * 0.5);
    path.cubicTo(w * 0.75, 0, w, h * 0.2, w, h * 0.5);
    path.cubicTo(w, h * 0.8, w * 0.75, h, w * 0.5, h * 0.5);

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.cyan, Color(0xFFC084FC)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Concentric Radar Rings Widget with orbiting dot (Figma Splash, Calling 6A & 6B)
class RadarPulseWidget extends StatefulWidget {
  final Widget child;
  final double size;
  const RadarPulseWidget({
    super.key,
    required this.child,
    this.size = 280,
  });

  @override
  State<RadarPulseWidget> createState() => _RadarPulseWidgetState();
}

class _RadarPulseWidgetState extends State<RadarPulseWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _RadarPainter(progress: _controller.value),
            child: Center(child: widget.child),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Draw static faint concentric circles
    final ringPaint = Paint()
      ..color = const Color(0xFF1E2D4A).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double f in [0.45, 0.65, 0.85, 1.0]) {
      canvas.drawCircle(center, maxRadius * f, ringPaint);
    }

    // Orbiting satellite dot
    final orbitAngle = progress * 2 * math.pi;
    final orbitRadius = maxRadius * 0.85;
    final dotX = center.dx + orbitRadius * math.cos(orbitAngle);
    final dotY = center.dy + orbitRadius * math.sin(orbitAngle);

    final dotPaint = Paint()
      ..color = AppColors.cyan
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(dotX, dotY), 4, dotPaint);

    // Glowing halo around dot
    final glowPaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(dotX, dotY), 8, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// SIM Detected & Verified Green Card (Figma screens 2A & 2B)
class SimVerifiedCard extends StatelessWidget {
  final String simLabel;
  final String phoneNumber;

  const SimVerifiedCard({
    super.key,
    this.simLabel = 'SIM 1: Jio 5G',
    this.phoneNumber = '+91 98765 43210',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2624),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF134E48), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.green, width: 1.5),
            ),
            child: const Icon(Icons.check, size: 14, color: AppColors.green),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SIM DETECTED & VERIFIED',
                  style: TextStyle(
                    color: AppColors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$simLabel • $phoneNumber',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// In-Call Audio Gauge Meter around avatar (Figma screen 8)
class AudioGaugeAvatar extends StatelessWidget {
  final String initials;
  final double size;

  const AudioGaugeAvatar({
    super.key,
    required this.initials,
    this.size = 110,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 36,
      height: size + 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size + 36, size + 36),
            painter: _GaugeTickPainter(),
          ),
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF2E3A59), Color(0xFF1E283F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugeTickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    const tickCount = 40;

    final tickPaint = Paint()
      ..color = const Color(0xFF244161)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < tickCount; i++) {
      final angle = (2 * math.pi / tickCount) * i;
      final start = Offset(
        center.dx + (radius - 7) * math.cos(angle),
        center.dy + (radius - 7) * math.sin(angle),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(start, end, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
