// 파일명: pharmacy_map_symbols_test.dart
// 역할: 약국 마커의 크기와 즐겨찾기 색상·아이콘을 검증한다.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/pharmacy_map_symbols.dart';

// 함수이름: main
// 함수역할: 지도 마커의 표시·크기 회귀 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 즐겨찾기 마커 렌더링 테스트
  // 함수역할: 선택 여부와 관계없이 골드색 별이 표시되고 기존 크기가 유지되는지 확인한다.
  // 매개변수: tester: 화면 제어기. 반환값: 비동기 검증 완료.
  testWidgets('favorite pins keep gold stars and stable bounds when selected', (
    tester,
  ) async {
    for (final selected in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: const Key('pin-image'),
              child: PharmacyMapPin(favorite: true, selected: selected),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(tester.getSize(find.byType(PharmacyMapPin)), PharmacyMapPin.size);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('pin-image')),
      );
      // 함수이름: runAsync 콜백
      // 함수역할: 실제 이미지 변환을 가상 시계 밖에서 완료하고 골드색 픽셀을 검증한다.
      // 매개변수: 없음. 반환값: 변환·검증 완료.
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (27 * image.width + 14) * 4;
        expect(bytes.getUint8(offset), 0xB8);
        expect(bytes.getUint8(offset + 1), 0x79);
        expect(bytes.getUint8(offset + 2), 0x00);
        expect(bytes.getUint8(offset + 3), 0xFF);
        image.dispose();
      });
    }
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: PharmacyMapPin())),
    );
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Function Name: selected pin aspect-ratio test
  // Description: Keep the enlarged selection proportional to the original artwork.
  // Parameters: none. Returns: completed dimension assertions.
  test('selected pharmacy pin preserves the slim artwork aspect ratio', () {
    expect(PharmacyMapPin.size.aspectRatio, lessThan(1));
    expect(
      PharmacyMapPin.selectedSize.aspectRatio,
      PharmacyMapPin.size.aspectRatio,
    );
  });

  // Function Name: map artwork bounds test
  // Description: Check the original marker and device-dot layout without a native map.
  // Parameters: tester controls layout. Returns: completed size assertions.
  testWidgets('vector pins and the blue dot render at their intended bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PharmacyMapPin(),
              PharmacyMapPin(selected: true),
              PharmacyDeviceLocationDot(),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(PharmacyMapPin).first),
      PharmacyMapPin.size,
    );
    expect(
      tester.getSize(find.byType(PharmacyDeviceLocationDot)),
      PharmacyDeviceLocationDot.size,
    );
  });
}
