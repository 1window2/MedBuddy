// 파일명: prescription_camera_orientation_service_test.dart
// 역할: 처방전 촬영 화면의 센서 회전 허용과 세로 복원 요청을 검증한다.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_camera_orientation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.medbuddy.app/prescription-camera-test');
  final methodCalls = <String>[];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('처방전 촬영 진입 시 센서 회전을 허용하고 종료 시 세로로 복원한다', () async {
    const service = PrescriptionCameraOrientationService(channel: channel);

    await service.enableSensorOrientation();
    await service.restorePortrait();

    expect(methodCalls, <String>[
      'enableSensorOrientation',
      'restorePortrait',
    ]);
  });

  test('Android 앱 기본 화면은 세로 방향으로 고정한다', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:screenOrientation="portrait"'));
  });

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
