// 파일명: prescription_camera_orientation_service_test.dart
// 역할: 처방전 촬영 화면의 세로 고정과 복원 요청을 검증한다.

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

  test('촬영 진입과 종료 시 세로 방향 정책을 유지한다', () async {
    const service = PrescriptionCameraOrientationService(channel: channel);

    await service.lockPortrait();
    await service.restorePortrait();

    expect(methodCalls, <String>['lockPortrait', 'restorePortrait']);
  });

  test('Android 진입 화면도 세로 방향으로 고정한다', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:screenOrientation="portrait"'));
  });
}
