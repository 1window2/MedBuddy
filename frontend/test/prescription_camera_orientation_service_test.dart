// File Name: prescription_camera_orientation_service_test.dart
// Role: Regression coverage for sensor rotation during prescription capture and portrait restoration.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_camera_orientation_service.dart';

// Function Name: main
// Description:
// - Register regression cases for sensor rotation during prescription capture and portrait
//   restoration.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.medbuddy.app/prescription-camera-test');
  final methodCalls = <String>[];

  // 함수이름: setUp 콜백
  // 함수역할:
  // - 방향 요청 기록을 비우고 플랫폼 채널을 요청명 기록용 대역으로 교체한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 메서드 채널 대역이 설치된다.
  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        // 함수이름: setMockMethodCallHandler 콜백
        // 함수역할:
        // - 시스템 방향 제어 메서드명을 기록하고 플랫폼 작업을 생략한다.
        // 매개변수:
        // - call (MethodCall): 테스트가 가로챈 플랫폼 메서드 호출.
        // 반환값:
        // - null로 완료되는 메서드 채널 응답.
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call.method);
          return null;
        });
  });

  // 함수이름: tearDown 콜백
  // 함수역할:
  // - 테스트용 방향 제어 채널 처리기를 제거해 다음 테스트에 남지 않게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 채널 대역이 해제된다.
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // Function Name: test callback
  // Description:
  // - Verify that prescription capture enables sensor rotation and restores portrait orientation on
  //   exit.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('처방전 촬영 진입 시 센서 회전을 허용하고 종료 시 세로로 복원한다', () async {
    const service = PrescriptionCameraOrientationService(channel: channel);

    await service.enableSensorOrientation();
    await service.restorePortrait();

    expect(methodCalls, <String>[
      'enableSensorOrientation',
      'restorePortrait',
    ]);
  });

  // Function Name: test callback
  // Description:
  // - Verify that the Android application defaults to portrait orientation.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Android 앱 기본 화면은 세로 방향으로 고정한다', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:screenOrientation="portrait"'));
  });

  // Function Name: test callback
  // Description:
  // - Verify that Android allows full sensor rotation only while the prescription camera is active.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Android는 처방전 촬영 중에만 전체 센서 회전을 허용한다', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/'
      'medbuddy_frontend/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('"enableSensorOrientation"'));
    expect(
      activity,
      contains('ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR'),
    );
    expect(activity, contains('ActivityInfo.SCREEN_ORIENTATION_PORTRAIT'));
  });
}
