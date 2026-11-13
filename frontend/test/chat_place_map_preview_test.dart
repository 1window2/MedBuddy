// 파일명: chat_place_map_preview_test.dart
// 역할: 채팅 장소 미리보기의 좌표 검증과 지도 대체 화면의 상세 이동·큰 글씨를 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:medbuddy_frontend/widgets/chat_place_map_preview.dart';

// 함수이름: main
// 함수역할:
// - 좌표 유효성 검사와 한영 지도 대체 화면 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록한 사례는 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: test callback
  // 함수역할:
  // - 원점·범위 밖 값·NaN·무한대는 거부하고 서울의 유효 좌표는 허용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
    // 함수이름: testWidgets callback
    // 함수역할:
    // - 무효 좌표에서 NaverMap을 만들지 않고 폭 240·글씨 배율 2의 대체 화면으로 상세 이동을 한 번 요청하는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
