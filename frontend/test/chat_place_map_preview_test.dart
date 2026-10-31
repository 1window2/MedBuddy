import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:medbuddy_frontend/widgets/chat_place_map_preview.dart';

void main() {
  test('없는 좌표나 범위 밖 좌표로 다른 장소를 표시하지 않는다', () {
    for (final point in [
      (0.0, 0.0),
      (91.0, 127.0),
      (37.0, -181.0),
      (double.nan, 0.0),
      (0.0, double.infinity),
    ]) {
      expect(ChatPlaceMapPreview.validCoordinates(point.$1, point.$2), isFalse);
    }
    expect(ChatPlaceMapPreview.validCoordinates(37.55, 126.92), isTrue);
  });
  for (final english in [false, true]) {
    testWidgets('미지원 지도는 상세 이동을 유지하고 큰 글씨도 표시 $english', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 240,
                child: ChatPlaceMapPreview(
                  latitude: 0,
                  longitude: 0,
                  isEnglish: english,
                  onOpen: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NaverMap), findsNothing);
      await tester.tap(find.byKey(const Key('chat-place-map-fallback')));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
