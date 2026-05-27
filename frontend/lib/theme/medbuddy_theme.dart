import 'package:flutter/material.dart';

class MedBuddyColors {
  static const Color primary = Color(0xFF009966);
  static const Color primaryDark = Color(0xFF007A55);
  static const Color mint = Color(0xFFD0FAE5);
  static const Color pageBackground = Color(0xFFF4FFF4);
  static const Color textStrong = Color(0xFF101828);
  static const Color textMuted = Color(0xFF4A5565);
  static const Color textLight = Color(0xFF99A1AF);
  static const Color infoBlue = Color(0xFF1C398E);
}

class MedBuddyRadii {
  static BorderRadius card = BorderRadius.circular(14);
  static BorderRadius largeCard = BorderRadius.circular(16);
  static BorderRadius pill = BorderRadius.circular(999);
}

class MedBuddyShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.12),
      blurRadius: 10,
      offset: Offset(0, 5),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.12),
      blurRadius: 14,
      offset: Offset(0, 8),
    ),
  ];
}
