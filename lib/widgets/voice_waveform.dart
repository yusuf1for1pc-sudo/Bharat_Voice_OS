import 'dart:math';
import 'package:flutter/material.dart';

/// A reusable animated voice waveform widget.
///
/// Accepts a [voiceLevel] (0.0–1.0) that controls the bar heights.
/// Reacts dynamically to real mic amplitude or TTS audio levels.
///
/// Usage:
/// ```dart
/// VoiceWaveform(
///   voiceLevel: 0.7,     // 0.0 = silent, 1.0 = max volume
///   barCount: 9,
///   color: Colors.white,
///   width: 120,
///   height: 40,
/// )
/// ```
class VoiceWaveform extends StatefulWidget {
  final double voiceLevel;
  final int barCount;
  final Color color;
  final double width;
  final double height;
  final double barWidth;

  const VoiceWaveform({
    super.key,
    this.voiceLevel = 0.5,
    this.barCount = 9,
    this.color = Colors.white,
    this.width = 120,
    this.height = 40,
    this.barWidth = 3.0,
  });

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _smoothedLevel = 0.0;
  List<double> _barTargets = [];
  List<double> _barHeights = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _barHeights = List.filled(widget.barCount, 4.0);
    _barTargets = List.filled(widget.barCount, 4.0);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateAnimation);
    
    _controller.repeat();
  }

  void _updateAnimation() {
    // Lerp _smoothedLevel towards incoming widget.voiceLevel
    _smoothedLevel = _smoothedLevel + (widget.voiceLevel - _smoothedLevel) * 0.3;
    
    // Base ambient noise gives a voiceLevel around ~0.45 to 0.55
    // so we clamp values below 0.45 to near zero, then scale up
    final activeLevel = (_smoothedLevel - 0.45).clamp(0.0, 1.0) * 2.0;
    
    for (int i = 0; i < widget.barCount; i++) {
        // Higher bars in the center
        final mid = (widget.barCount - 1) / 2.0;
        final dist = (i - mid).abs();
        final centerWeight = 1.0 - (dist / mid) * 0.6; // 1.0 at center, 0.4 at edges
        
        // Add proportional visual flutter when volume is up
        final flutter = _random.nextDouble() * 0.6 + 0.7; // 0.7 to 1.3
        
        final maxBarHeight = widget.height;
        final target = maxBarHeight * activeLevel * centerWeight * flutter;
        _barTargets[i] = max(target, 4.0); // minimum 4.0 px dot
        
        // Lerp current height to target to smooth out spikes
        _barHeights[i] = _barHeights[i] + (_barTargets[i] - _barHeights[i]) * 0.3;
    }
    setState(() {}); // trigger repaint
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _WaveformPainter(
        barHeights: _barHeights,
        color: widget.color,
        barWidth: widget.barWidth,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> barHeights;
  final Color color;
  final double barWidth;

  _WaveformPainter({
    required this.barHeights,
    required this.color,
    required this.barWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final barCount = barHeights.length;
    // Distribute bars evenly
    final barSpacing = size.width / (barCount + 1);
    final centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final x = barSpacing * (i + 1);
      final h = barHeights[i];
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}
