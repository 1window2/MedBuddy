// 파일명: prescription_camera_orientation_service_test.dart
// 역할: 처방전 촬영 화면의 센서 회전 허용과 복원 요청을 검증한다.

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

  test('촬영 진입과 종료 시 센서 회전 허용 뒤 기존 방향을 복원한다', () async {
    const service = PrescriptionCameraOrientationService(channel: channel);

    await service.enableSensorRotation();
    await service.restoreOrientation();

    expect(methodCalls, <String>['enableSensorRotation', 'restoreOrientation']);
  });
}
