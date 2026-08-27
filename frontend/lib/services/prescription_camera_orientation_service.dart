// 파일명: prescription_camera_orientation_service.dart
// 역할: 처방전 촬영 중에만 기기 센서 방향을 따르도록 네이티브 화면 회전을 제어한다.

import 'package:flutter/services.dart';

// 클래스명: PrescriptionCameraOrientationService
// 역할: 처방전 촬영 화면의 회전 허용과 기존 방향 복원을 Android에 요청한다.
class PrescriptionCameraOrientationService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.medbuddy.app/prescription-camera',
  );

  final MethodChannel _channel;

  const PrescriptionCameraOrientationService({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  // 함수명: enableSensorRotation
  // 함수역할:
  // - 휴대폰의 자동 회전 잠금 여부와 관계없이 촬영 화면이 센서 방향을 따르도록 요청한다.
  // 반환값:
  // - 네이티브 방향 정책 적용 요청이 끝나면 완료된다.
  Future<void> enableSensorRotation() async {
    await _invokeSafely('enableSensorRotation');
  }

  // 함수명: restoreOrientation
  // 함수역할:
  // - 촬영 화면을 열기 전에 사용하던 앱 방향 정책을 복원한다.
  // 반환값:
  // - 네이티브 방향 정책 복원 요청이 끝나면 완료된다.
  Future<void> restoreOrientation() async {
    await _invokeSafely('restoreOrientation');
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
