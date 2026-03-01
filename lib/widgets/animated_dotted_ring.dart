import 'dart:math';
import 'package:flutter/material.dart';
import '../painters/dotted_ring_painter.dart';
import '../models/app_state.dart';

/// Animated wrapper around DottedRingPainter that handles
/// breathing, rotation, and morph animations via AnimationController.
class AnimatedDottedRing extends StatefulWidget {
  final RingState state;
  final List<double>? audioAmplitudes;

  const AnimatedDottedRing({
    super.key,
    required this.state,
    this.audioAmplitudes,
  });

  @override
  State<AnimatedDottedRing> createState() => _AnimatedDottedRingState();
}

class _AnimatedDottedRingState extends State<AnimatedDottedRing>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _rotationController;
  late AnimationController _morphController;

  @override
  void initState() {
    super.initState();

    // Breathing animation
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    // Rotation animation
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    )..repeat();

    // Morph animation (circle ↔ blob)
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didUpdateWidget(AnimatedDottedRing oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.state != oldWidget.state) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    switch (widget.state) {
      case RingState.idle:
        _breathController.duration = const Duration(milliseconds: 3000);
        _rotationController.duration = const Duration(milliseconds: 12000);
        _morphController.reverse();
        break;
      case RingState.active:
        _breathController.duration = const Duration(milliseconds: 2000);
        _rotationController.duration = const Duration(milliseconds: 8000);
        _morphController.forward();
        break;
      case RingState.listening:
        _breathController.duration = const Duration(milliseconds: 1500);
        _rotationController.duration = const Duration(milliseconds: 10000);
        _morphController.reverse();
        break;
      case RingState.processing:
        _breathController.duration = const Duration(milliseconds: 2000);
        _rotationController.duration = const Duration(milliseconds: 3000);
        _morphController.forward();
        break;
    }

    if (!_breathController.isAnimating) {
      _breathController.repeat(reverse: true);
    }
    if (!_rotationController.isAnimating) {
      _rotationController.repeat();
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _rotationController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _breathController,
        _rotationController,
        _morphController,
      ]),
      builder: (context, child) {
        final breathScale = 1.0 + (_breathController.value - 0.5) * 0.06; // ±3%
        final rotationAngle = _rotationController.value * 2 * pi;
        final morphProgress = _morphController.value;

        return CustomPaint(
          painter: DottedRingPainter(
            morphProgress: morphProgress,
            rotationAngle: rotationAngle,
            breathScale: breathScale,
            audioAmplitudes: widget.audioAmplitudes,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}
