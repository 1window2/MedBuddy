// 파일명: prescription_camera_orientation_service.dart
// 역할: 처방전 촬영 중에만 네이티브 센서 회전을 허용하고 종료 후 세로 방향을 복원한다.

import 'package:flutter/services.dart';

// 클래스명: PrescriptionCameraOrientationService
// 역할: 처방전 촬영 화면의 센서 회전 허용과 세로 정책 복원을 Android에 요청한다.
class PrescriptionCameraOrientationService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.medbuddy.app/prescription-camera',
  );

  final MethodChannel _channel;

  const PrescriptionCameraOrientationService({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  // 함수명: enableSensorOrientation
  // 함수역할:
  // - 처방전 촬영 화면에서만 세로와 가로 센서 회전을 허용하도록 요청한다.
  Future<void> enableSensorOrientation() async {
    await _invokeSafely('enableSensorOrientation');
  }

  // 함수명: restorePortrait
  // 함수역할:
  // - 처방전 촬영 화면을 열기 전에 사용하던 세로 방향 정책을 복원한다.
  Future<void> restorePortrait() async {
    await _invokeSafely('restorePortrait');
  }

  Future<void> _invokeSafely(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Android가 아닌 플랫폼과 위젯 테스트에서는 네이티브 회전 제어 없이 계속 진행한다.
    } on PlatformException {
      // 방향 전환을 지원하지 않는 기기에서도 촬영 자체는 계속 사용할 수 있게 한다.
    }
  }
}
