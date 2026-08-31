// 파일명: prescription_camera_layout_service.dart
// 역할: 처방전 촬영 화면의 배치와 실제 이미지 자르기가 공유할 좌표를 계산한다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

// 클래스명: PrescriptionCameraLayoutService
// 역할: 회전 중 늦게 전달되는 센서 값이 잘못된 배치를 유지하지 않도록 화면 크기를 우선한다.
class PrescriptionCameraLayoutService {
  static const double prescriptionAspectRatio = 21.5 / 15;
  static const double landscapeGuideWidthFactor = 0.90;
  static const double landscapeGuideHeightFactor = 0.80;
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

  // 함수명: guideRect
  // 역할:
  // - 세로 화면의 기존 가이드 크기는 유지한다.
  // - 가로 화면에서는 처방전이 더 많은 픽셀을 차지하도록 가이드를 넓힌다.
  static Rect guideRect(Size viewportSize) {
    if (viewportSize.isEmpty) {
      return Rect.zero;
    }

    final isLandscape = viewportSize.width > viewportSize.height;
    final maximumWidth =
        viewportSize.width * (isLandscape ? landscapeGuideWidthFactor : 0.86);
    final maximumHeight =
        viewportSize.height * (isLandscape ? landscapeGuideHeightFactor : 0.58);
    final preferredHeight = maximumWidth / prescriptionAspectRatio;
    final guideHeight = preferredHeight <= maximumHeight
        ? preferredHeight
        : maximumHeight;
    final guideWidth = guideHeight * prescriptionAspectRatio;
    final top = isLandscape
        ? (viewportSize.height - guideHeight) / 2
        : viewportSize.height * 0.12;

    return Rect.fromLTWH(
      (viewportSize.width - guideWidth) / 2,
      top,
      guideWidth,
      guideHeight,
    );
  }

  // 함수명: normalizedSourceRect
  // 역할:
  // - BoxFit.cover로 표시된 미리보기의 가이드 좌표를 원본 이미지의 0~1 좌표로 변환한다.
  // - 화면에 보인 가이드와 촬영 결과의 자르기 영역이 항상 일치하도록 한다.
  static Rect normalizedSourceRect({
    required Size viewportSize,
    required Size displayedImageSize,
    required Rect guideRect,
  }) {
    if (viewportSize.isEmpty ||
        displayedImageSize.isEmpty ||
        guideRect.isEmpty) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    final scale = math.max(
      viewportSize.width / displayedImageSize.width,
      viewportSize.height / displayedImageSize.height,
    );
    final renderedSize = Size(
      displayedImageSize.width * scale,
      displayedImageSize.height * scale,
    );
    final horizontalOffset = (viewportSize.width - renderedSize.width) / 2;
    final verticalOffset = (viewportSize.height - renderedSize.height) / 2;

    final left = ((guideRect.left - horizontalOffset) / renderedSize.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final top = ((guideRect.top - verticalOffset) / renderedSize.height)
        .clamp(0.0, 1.0)
        .toDouble();
    final right = ((guideRect.right - horizontalOffset) / renderedSize.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final bottom = ((guideRect.bottom - verticalOffset) / renderedSize.height)
        .clamp(0.0, 1.0)
        .toDouble();
    if (right <= left || bottom <= top) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
