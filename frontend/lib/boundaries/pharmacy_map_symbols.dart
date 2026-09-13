import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

/// Fixed-aspect vector artwork; rendered once per map, not per pharmacy.
class PharmacyMapPin extends StatelessWidget {
  const PharmacyMapPin({super.key, this.selected = false});
  final bool selected;
  static const size = Size(28, 40);
  static const selectedSize = Size(35, 50);

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: size,
    painter: _PharmacyPinPainter(
      selected ? MedBuddyColors.primaryDark : MedBuddyColors.primary,
    ),
  );
}

class _PharmacyPinPainter extends CustomPainter {
  const _PharmacyPinPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 40);
    final path = Path()
      ..moveTo(14, 38)
      ..cubicTo(11, 31, 2, 23, 2, 14)
      ..cubicTo(2, -2, 26, -2, 26, 14)
      ..cubicTo(26, 23, 17, 31, 14, 38)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(path, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(10, 14), const Offset(18, 14), cross);
    canvas.drawLine(const Offset(14, 10), const Offset(14, 18), cross);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PharmacyPinPainter oldDelegate) => oldDelegate.color != color;
}

class PharmacyDeviceLocationDot extends StatelessWidget {
  const PharmacyDeviceLocationDot({super.key});
  static const size = Size.square(30);

  @override
  Widget build(BuildContext context) => Container(
    width: size.width,
    height: size.height,
    padding: const EdgeInsets.all(6),
    decoration: const BoxDecoration(
      color: Color(0x332563EB), shape: BoxShape.circle,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
      ),
    ),
  );
}
