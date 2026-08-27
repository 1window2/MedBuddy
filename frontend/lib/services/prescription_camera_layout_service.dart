// 파일명: prescription_camera_layout_service.dart
// 역할: 실제 화면 비율을 기준으로 처방전 촬영 화면의 세로·가로 배치를 결정한다.

import 'package:flutter/material.dart';

// 클래스명: PrescriptionCameraLayoutService
// 역할: 회전 중 늦게 전달되는 센서 값이 잘못된 배치를 유지하지 않도록 화면 크기를 우선한다.
class PrescriptionCameraLayoutService {
  static const double minimumLandscapePanelWidth = 196;
  static const double maximumLandscapePanelWidth = 260;

  const PrescriptionCameraLayoutService._();

  // 함수명: shouldUseLandscapeLayout
  // 역할:
  // - 화면 비율이 명확하면 실제 화면 크기를 우선한다.
  // - 회전 중 화면이 정사각형에 가까울 때만 카메라 센서 방향을 보조로 사용한다.
  static bool shouldUseLandscapeLayout({
    required Size viewportSize,
    bool cameraReportsLandscape = false,
  }) {
    if (viewportSize.isEmpty) {
      return cameraReportsLandscape;
    }
    const decisiveAspectRatio = 1.10;
    if (viewportSize.width >= viewportSize.height * decisiveAspectRatio) {
      return true;
    }
    if (viewportSize.height >= viewportSize.width * decisiveAspectRatio) {
      return false;
    }
    return cameraReportsLandscape;
  }

  // 함수명: landscapePanelWidth
  // 역할: 가로 화면에서 촬영 조작 패널이 미리보기를 과도하게 가리지 않도록 너비를 제한한다.
  static double landscapePanelWidth(Size viewportSize) {
    return (viewportSize.width * 0.30)
        .clamp(minimumLandscapePanelWidth, maximumLandscapePanelWidth)
        .toDouble();
  }
}
