import 'dart:math';
import 'package:flutter/material.dart';

/// A circular/radial voice waveform orb for AI speech visualization.
///
/// When [voiceLevel] is 0, the orb is a calm glowing circle.
/// As [voiceLevel] increases, radial "rays" pulse outward, creating
/// a sun-like voice visualization. Different visual style from the
/// bar-based [VoiceWaveform] used for user speech.
///
/// In the future, connect [voiceLevel] to real TTS audio amplitude.
class AiVoiceOrb extends StatefulWidget {
  final double voiceLevel;
  final double size;
  final Color color;

  const AiVoiceOrb({
    super.key,
    this.voiceLevel = 0.0,
    this.size = 180,
    this.color = Colors.white,
  });

  @override
  State<AiVoiceOrb> createState() => _AiVoiceOrbState();
}

class _AiVoiceOrbState extends State<AiVoiceOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _AiOrbPainter(
            phase: _controller.value,
            voiceLevel: widget.voiceLevel,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _AiOrbPainter extends CustomPainter {
  final double phase;
  final double voiceLevel;
  final Color color;

  _AiOrbPainter({
    required this.phase,
    required this.voiceLevel,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final level = voiceLevel.clamp(0.0, 1.0);

    // ─── Outer glow (pulsing with voice) ───
    final glowRadius = maxRadius * (0.7 + level * 0.3);
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.03 + level * 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(center, glowRadius, glowPaint);

    // ─── Radial rays (voice-reactive) ───
    final rayCount = 48;
    final random = Random(77); // fixed seed for consistent pattern
    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * pi * 2 + phase * pi * 2;

      // Each ray has a unique base height + sine wave modulated by voice
      final baseLen = random.nextDouble() * 0.3 + 0.1;
      final wave = sin(angle * 3 + phase * pi * 4) * 0.5 + 0.5;
      final voiceBoost = level * wave * 0.5;
      final rayLength = maxRadius * (baseLen * 0.3 + voiceBoost);

      // Inner radius = core circle edge
      final coreRadius = maxRadius * 0.32;
      final innerR = coreRadius;
      final outerR = coreRadius + rayLength;

      final x1 = center.dx + cos(angle) * innerR;
      final y1 = center.dy + sin(angle) * innerR;
      final x2 = center.dx + cos(angle) * outerR;
      final y2 = center.dy + sin(angle) * outerR;

      final rayAlpha = (0.15 + level * 0.5) * (0.5 + wave * 0.5);
      final rayPaint = Paint()
        ..color = color.withValues(alpha: rayAlpha.clamp(0.0, 1.0))
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), rayPaint);
    }

    // ─── Core circle (solid, slightly pulsing) ───
    final coreScale = 1.0 + level * 0.1 * sin(phase * pi * 2);
    final coreRadius = maxRadius * 0.32 * coreScale;

    // Core gradient
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.15 + level * 0.15),
          color.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    // Core border ring
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.2 + level * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, coreRadius, borderPaint);

    // ─── Inner dot ───
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.3 + level * 0.4);
    canvas.drawCircle(center, 3, dotPaint);
  }

  @override
  bool shouldRepaint(_AiOrbPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.voiceLevel != voiceLevel;
}
