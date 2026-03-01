import 'dart:math';
import 'package:flutter/material.dart';

/// Custom painter that draws the iconic dotted ring / blob.
/// The ring is composed of individual dots arranged in concentric layers
/// with halftone-style density variation (denser/larger at top, sparser at bottom).
class DottedRingPainter extends CustomPainter {
  /// 0.0 = perfect circle (idle), 1.0 = fully morphed blob (active)
  final double morphProgress;

  /// Slow rotation angle in radians
  final double rotationAngle;

  /// Breathing scale factor (1.0 = normal, oscillates ±3%)
  final double breathScale;

  /// Optional per-dot audio amplitude array for listening state
  final List<double>? audioAmplitudes;

  /// Random seed for consistent organic irregularity
  final int seed;

  DottedRingPainter({
    required this.morphProgress,
    required this.rotationAngle,
    required this.breathScale,
    this.audioAmplitudes,
    this.seed = 42,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = min(size.width, size.height) * 0.38;
    final rng = Random(seed);

    // Pre-generate blob shape offsets (4-5 bumps)
    final blobOffsets = _generateBlobOffsets(rng);

    // Draw multiple concentric layers to create the thick band
    const int layerCount = 8;
    const double bandWidth = 30.0;

    for (int layer = 0; layer < layerCount; layer++) {
      final layerOffset = (layer - layerCount / 2) * (bandWidth / layerCount);
      final layerRadius = baseRadius + layerOffset;

      // More dots in outer layers, fewer in inner
      final dotCount = 120 + layer * 15;

      for (int i = 0; i < dotCount; i++) {
        final angle = (i / dotCount) * 2 * pi + rotationAngle;

        // Calculate radius at this angle
        double r = layerRadius * breathScale;

        // Add organic irregularity to base circle (±5%)
        final irregularity = _organicNoise(angle, rng, i + layer * 1000) * 0.05;
        r += r * irregularity;

        // Morph toward blob shape
        if (morphProgress > 0) {
          final blobR = _blobRadius(angle, baseRadius * 1.3, blobOffsets);
          r = r * (1 - morphProgress) + blobR * morphProgress * breathScale;
        }

        // Audio reactivity
        if (audioAmplitudes != null && audioAmplitudes!.isNotEmpty) {
          final ampIndex = (i * audioAmplitudes!.length / dotCount).floor();
          r += audioAmplitudes![ampIndex % audioAmplitudes!.length] * 8.0;
        }

        // Position
        final x = center.dx + r * cos(angle);
        final y = center.dy + r * sin(angle);

        // Halftone effect: dots at top (angle near -pi/2) are larger and brighter
        // Dots at bottom (angle near pi/2) are smaller and dimmer
        final normalizedAngle = (angle % (2 * pi));
        // Top of circle = -pi/2 (or 3*pi/2). Map to 0..1 where 0=top, 1=bottom
        final topness = (1 - cos(normalizedAngle - pi)) / 2; // 0=bottom, 1=top
        final adjustedTopness = topness * 0.7 + 0.3; // Clamp range

        // Dot size: 2dp to 5dp based on position + random variation
        final sizeVariation = rng.nextDouble() * 0.4 + 0.8;
        final dotSize = (2.0 + adjustedTopness * 3.0) * sizeVariation;

        // Dot opacity: 5% to 100% based on position + layer depth
        final layerFade = 1.0 - (layerOffset.abs() / (bandWidth / 2)) * 0.5;
        final dotOpacity = (0.05 + adjustedTopness * 0.95) * layerFade;

        // Some random dropout for organic feel
        if (rng.nextDouble() > 0.15 + adjustedTopness * 0.7) continue;

        final paint = Paint()
          ..color = Colors.white.withValues(alpha: dotOpacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(x, y), dotSize / 2, paint);
      }
    }
  }

  /// Generate 4-5 blob bumps with random amplitudes
  List<_BlobBump> _generateBlobOffsets(Random rng) {
    final count = 4 + rng.nextInt(2); // 4 or 5 bumps
    return List.generate(count, (i) {
      return _BlobBump(
        angle: (i / count) * 2 * pi + 0.3, // offset so bumps aren't aligned
        amplitude: 0.15 + rng.nextDouble() * 0.25, // 15% to 40% extra radius
        width: 0.8 + rng.nextDouble() * 0.6, // bump width in radians
      );
    });
  }

  /// Calculate blob radius at a given angle
  double _blobRadius(double angle, double baseR, List<_BlobBump> bumps) {
    double r = baseR;
    for (final bump in bumps) {
      final diff = _angleDiff(angle, bump.angle);
      if (diff.abs() < bump.width) {
        r += baseR * bump.amplitude * cos(diff / bump.width * pi / 2);
      }
    }
    return r;
  }

  /// Angle difference normalized to [-pi, pi]
  double _angleDiff(double a, double b) {
    double d = a - b;
    while (d > pi) { d -= 2 * pi; }
    while (d < -pi) { d += 2 * pi; }
    return d;
  }

  /// Organic noise function for slight radius variation
  double _organicNoise(double angle, Random rng, int seed) {
    // Simple deterministic noise based on angle and seed
    final s = sin(angle * 3 + seed * 0.1) * cos(angle * 5 + seed * 0.2);
    return s;
  }

  @override
  bool shouldRepaint(DottedRingPainter oldDelegate) {
    return morphProgress != oldDelegate.morphProgress ||
        rotationAngle != oldDelegate.rotationAngle ||
        breathScale != oldDelegate.breathScale ||
        audioAmplitudes != oldDelegate.audioAmplitudes;
  }
}

class _BlobBump {
  final double angle;
  final double amplitude;
  final double width;
  _BlobBump({required this.angle, required this.amplitude, required this.width});
}
