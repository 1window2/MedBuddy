import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_text_scale.dart';

// 파일명: medbuddy_text_scale_test.dart
// 역할: 앱 글씨 크기 설정이 전역 배율로 한 번만 적용되는지 검증한다.

void main() {
  test('글씨 크기 옵션은 작게·중간·크게를 명확한 전역 배율로 변환한다', () {
    expect(const UserSetting(fontSize: 14).preferredTextScale, 0.92);
    expect(const UserSetting(fontSize: 16).preferredTextScale, 1.0);
    expect(const UserSetting(fontSize: 20).preferredTextScale, 1.30);
  });

  test('운영체제 접근성 배율을 축소하지 않고 최종 배율을 2배로 제한한다', () {
    const smallSetting = UserSetting(fontSize: 14);
    const largeSetting = UserSetting(fontSize: 20);

    expect(smallSetting.resolveTextScale(1.0), 0.92);
    expect(smallSetting.resolveTextScale(1.6), 1.6);
    expect(largeSetting.resolveTextScale(1.0), 1.30);
    expect(largeSetting.resolveTextScale(2.4), 2.0);
  });

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
