import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

// 파일명: flutter_test_config.dart
// 역할: 필요할 때 전체 위젯 테스트에 동일한 접근성 글씨 배율을 적용한다.

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const requestedScaleValue = String.fromEnvironment(
    'MEDBUDDY_TEST_TEXT_SCALE',
    defaultValue: '1',
  );
  final requestedScale = double.tryParse(requestedScaleValue) ?? 1;
  if (requestedScale != 1) {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.textScaleFactorTestValue = requestedScale;
    });
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
  await testMain();
}
