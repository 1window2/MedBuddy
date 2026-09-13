// 파일명: medbuddy_text_scale_test.dart
// 역할: 앱 글씨 크기 설정이 전역 배율로 한 번만 적용되는지 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_text_scale.dart';


// 함수이름: main
// 함수역할:
// - 전역 글씨 배율과 운영체제 접근성 배율 제한 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 글씨 크기 옵션은 작게·중간·크게를 명확한 전역 배율로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('글씨 크기 옵션은 작게·중간·크게를 명확한 전역 배율로 변환한다', () {
    expect(const UserSetting(fontSize: 14).preferredTextScale, 0.92);
    expect(const UserSetting(fontSize: 16).preferredTextScale, 1.0);
    expect(const UserSetting(fontSize: 20).preferredTextScale, 1.30);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 운영체제 접근성 배율을 축소하지 않고 최종 배율을 2배로 제한한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('운영체제 접근성 배율을 축소하지 않고 최종 배율을 2배로 제한한다', () {
    const smallSetting = UserSetting(fontSize: 14);
    const largeSetting = UserSetting(fontSize: 20);

    expect(smallSetting.resolveTextScale(1.0), 0.92);
    expect(smallSetting.resolveTextScale(1.6), 1.6);
    expect(largeSetting.resolveTextScale(1.0), 1.30);
    expect(largeSetting.resolveTextScale(2.4), 2.0);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: MedBuddyTextScale은 모든 하위 화면에 큰 글씨 배율을 전달한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('MedBuddyTextScale은 모든 하위 화면에 큰 글씨 배율을 전달한다', (tester) async {
    double? resolvedTextScale;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.0),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MedBuddyTextScale(
            userSetting: const UserSetting(fontSize: 20),
            child: Builder(
              // 함수이름: builder 콜백
              // 함수역할:
              // - 하위 위젯의 실제 글씨 배율을 측정하고 식별용 텍스트를 표시한다.
              // 매개변수:
              // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
              // 반환값:
              // - 측정 대상 Text 위젯; 적용 배율은 외부 변수에 기록된다.
              builder: (context) {
                resolvedTextScale =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                return const Text('MedBuddy');
              },
            ),
          ),
        ),
      ),
    );

    expect(resolvedTextScale, 1.30);
    expect(tester.takeException(), isNull);
  });
}
