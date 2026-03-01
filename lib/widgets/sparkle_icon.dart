import 'package:flutter/material.dart';

/// Four-pointed sparkle/star icon as seen in the reference images.
/// A compass-rose style star with long thin points.
class SparkleIcon extends StatelessWidget {
  final double size;
  final Color color;

  const SparkleIcon({
    super.key,
    this.size = 48,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SparklePainter(color: color),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final Color color;
  _SparklePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    final narrow = r * 0.12; // thin waist

    final path = Path();
    // Top point
    path.moveTo(cx, 0);
    path.quadraticBezierTo(cx + narrow, cy - narrow, cx + r * 0.3, cy);
    // Right point
    path.lineTo(size.width, cy);
    path.quadraticBezierTo(cx + narrow, cy + narrow, cx, size.height);
    // Bottom point
    path.lineTo(cx, size.height);
    path.quadraticBezierTo(cx - narrow, cy + narrow, 0, cy);
    // Left point
    path.lineTo(0, cy);
    path.quadraticBezierTo(cx - narrow, cy - narrow, cx, 0);

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
