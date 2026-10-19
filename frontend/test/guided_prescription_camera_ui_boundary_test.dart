// 파일명: guided_prescription_camera_ui_boundary_test.dart
// 역할: 처방전 촬영 화면이 카메라 실패를 현지화한 문구로 안내하고 권한 거부 시 앱 설정 열기를 제공하는지 검증한다.
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/guided_prescription_camera_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: _pumpCamera
// 함수역할: 카메라 목록 조회가 지정한 오류로 실패하는 촬영 화면을 띄운다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작 도구.
// - error (CameraException): 카메라 목록 조회가 던질 오류.
// - onOpenSettings (Future<bool> Function()): 앱 설정 열기 대역.
// - language (String): 화면 언어 코드.
// 반환값: 화면이 안정되면 완료되는 Future<void>.
Future<void> _pumpCamera(
  WidgetTester tester,
  CameraException error, {
  required Future<bool> Function() onOpenSettings,
  String language = 'ko',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GuidedPrescriptionCameraUI(
        userSetting: UserSetting(language: language),
        cameraListProvider: () async => throw error,
        appSettingsOpener: onOpenSettings,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할: 카메라 실패 안내 회귀 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 권한 거부 테스트
  // 함수역할: 권한이 거부되면 권한 안내와 함께 설정 열기·다시 시도를 제공하고 설정 열기를 요청하는지 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('권한이 거부되면 설정 열기를 제공한다', (tester) async {
    var opened = 0;
    await _pumpCamera(
      tester,
      CameraException('CameraAccessDenied', 'User denied camera access.'),
      onOpenSettings: () async {
        opened += 1;
        return true;
      },
    );
    expect(find.textContaining('카메라 권한이 필요합니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 플랫폼 설명 숨김 테스트
  // 함수역할: 권한 외 오류는 영어 플랫폼 설명 대신 현지화한 문구를 보이고 설정 열기는 숨기는지 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('기타 카메라 오류는 현지화한 문구만 보인다', (tester) async {
    await _pumpCamera(
      tester,
      CameraException('cameraNotReadable', 'Camera HAL failed to open id 0'),
      onOpenSettings: () async => true,
    );
    expect(find.text('카메라를 사용할 수 없습니다.'), findsOneWidget);
    expect(find.textContaining('HAL'), findsNothing);
    expect(find.text('설정 열기'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
