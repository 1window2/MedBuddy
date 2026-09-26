// 파일명: flutter_test_config.dart
// 역할: 필요할 때 전체 위젯 테스트에 동일한 접근성 글씨 배율을 적용한다.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';


// 함수이름: testExecutable
// 함수역할:
// - 환경 변수의 글씨 배율을 공통 설정·정리 훅에 적용한 뒤 테스트 진입점을 실행한다.
// 매개변수:
// - testMain (FutureOr<void> Function()): 공통 설정으로 감싸 실행할 테스트 묶음 진입점.
// 반환값:
// - 전체 테스트 진입점 실행 완료.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const requestedScaleValue = String.fromEnvironment(
    'MEDBUDDY_TEST_TEXT_SCALE',
    defaultValue: '1',
  );
  final requestedScale = double.tryParse(requestedScaleValue) ?? 1;
  if (requestedScale != 1) {
    // 함수이름: setUp 콜백
    // 함수역할:
    // - 각 위젯 테스트 전에 요청한 시스템 글씨 배율을 테스트 바인딩에 적용한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 플랫폼 글씨 배율이 설정된다.
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.textScaleFactorTestValue = requestedScale;
    });
    // 함수이름: tearDown 콜백
    // 함수역할:
    // - 각 위젯 테스트 뒤에 덮어쓴 시스템 글씨 배율을 제거한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 테스트용 글씨 배율이 해제된다.
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
  await testMain();
}
