// 파일명: prescription_camera_orientation_service.dart
// 역할: 처방전 촬영 중에만 네이티브 센서 회전을 허용하고 종료 후 세로 방향을 복원한다.

import 'package:flutter/services.dart';

// 클래스명: PrescriptionCameraOrientationService
// 역할: 처방전 촬영 중 네이티브 화면 방향 설정을 제어한다.
// 주요 책임: 센서 방향 사용과 세로 방향 복원을 플랫폼 채널에 요청한다.
// 속성: _channel (MethodChannel): 주입 가능한 네이티브 호출 경계; _defaultChannel: 앱의 처방전 카메라 채널.
class PrescriptionCameraOrientationService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.medbuddy.app/prescription-camera',
  );

  final MethodChannel _channel;

  // 함수이름: PrescriptionCameraOrientationService
  // 함수역할: 처방전 촬영 방향 정책을 요청할 네이티브 메서드 채널을 연결한다.
  // 매개변수:
  // - channel (MethodChannel): 촬영 방향 정책을 요청할 네이티브 채널
  // 반환값:
  // - PrescriptionCameraOrientationService: 초기화된 인스턴스.
  const PrescriptionCameraOrientationService({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  // Function Name: enableSensorOrientation
  // Description: Requests sensor-based portrait and landscape rotation while the prescription capture screen is active.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> enableSensorOrientation() async {
    await _invokeSafely('enableSensorOrientation');
  }

  // Function Name: restorePortrait
  // Description: Restores the portrait-orientation policy used before entering prescription capture.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> restorePortrait() async {
    await _invokeSafely('restorePortrait');
  }

  // 함수이름: _invokeSafely
  // 함수역할: 방향 정책 메서드를 네이티브에 전달하고 미지원 플러그인 또는 플랫폼 실패는 화면으로 전파하지 않는다.
  // 매개변수:
  // - method (String): 네이티브 방향 정책 메서드 이름
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
