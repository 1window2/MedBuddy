import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/pharmacy_map_symbols.dart';

void main() {
  test('selected pharmacy pin preserves the slim artwork aspect ratio', () {
    expect(PharmacyMapPin.size.aspectRatio, lessThan(1));
    expect(PharmacyMapPin.selectedSize.aspectRatio,
        PharmacyMapPin.size.aspectRatio);
  });

  testWidgets('vector pins and the blue dot render at their intended bounds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [PharmacyMapPin(), PharmacyMapPin(selected: true),
        PharmacyDeviceLocationDot()],
    ))));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PharmacyMapPin).first), PharmacyMapPin.size);
    expect(tester.getSize(find.byType(PharmacyDeviceLocationDot)),
        PharmacyDeviceLocationDot.size);
  });
}
