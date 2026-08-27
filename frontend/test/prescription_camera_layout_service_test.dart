// 파일명: prescription_camera_layout_service_test.dart
// 역할: 처방전 촬영 화면이 회전 직후에도 실제 화면 비율에 맞는 배치를 사용하는지 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_camera_layout_service.dart';

void main() {
  test('명확한 화면 비율은 늦게 갱신된 카메라 방향보다 우선한다', () {
    expect(
      PrescriptionCameraLayoutService.shouldUseLandscapeLayout(
        viewportSize: const Size(700, 390),
      ),
      isTrue,
    );
    expect(
      PrescriptionCameraLayoutService.shouldUseLandscapeLayout(
        viewportSize: const Size(390, 700),
        cameraReportsLandscape: true,
      ),
      isFalse,
    );
  });

  test('회전 중 화면 비율이 비슷할 때만 카메라 방향을 보조로 사용한다', () {
    expect(
      PrescriptionCameraLayoutService.shouldUseLandscapeLayout(
        viewportSize: const Size(410, 400),
        cameraReportsLandscape: true,
      ),
      isTrue,
    );
    expect(
      PrescriptionCameraLayoutService.shouldUseLandscapeLayout(
        viewportSize: const Size(400, 410),
      ),
      isFalse,
    );
  });

  test('가로 조작 패널 너비를 화면 크기에 맞게 제한한다', () {
    expect(
      PrescriptionCameraLayoutService.landscapePanelWidth(const Size(600, 300)),
      PrescriptionCameraLayoutService.minimumLandscapePanelWidth,
    );
    expect(
      PrescriptionCameraLayoutService.landscapePanelWidth(
        const Size(1200, 600),
      ),
      PrescriptionCameraLayoutService.maximumLandscapePanelWidth,
    );
  });
}
