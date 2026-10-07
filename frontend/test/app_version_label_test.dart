// 파일명: app_version_label_test.dart
// 역할: 설정 화면의 앱 버전 표시가 누락되지 않는지 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/app_version_label.dart';

// 함수이름: main
// 함수역할:
// - 설정 화면의 앱 버전 표시 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 설정 화면에 전달된 앱 버전을 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('설정 화면에 전달된 앱 버전을 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppVersionLabel(version: '0.2.0')),
      ),
    );

    expect(find.byKey(const ValueKey('appVersionLabel')), findsOneWidget);
    expect(find.text('MedBuddy v0.2.0'), findsOneWidget);
  });
}
