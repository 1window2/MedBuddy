import 'dart:math' as math;

import 'package:flutter/material.dart';

// 파일명: prescription_guide_layout.dart
// 역할: 처방전 촬영 가이드와 실제 이미지 자르기가 공유할 좌표를 계산한다.

// 클래스명: PrescriptionGuideLayout
// 역할: 세로·가로 화면에 맞는 가이드 영역과 원본 이미지 기준 자르기 비율을 제공한다.
class PrescriptionGuideLayout {
  static const double prescriptionAspectRatio = 1.5;
  static const double minimumLandscapePanelWidth = 196;
  static const double maximumLandscapePanelWidth = 260;

  const PrescriptionGuideLayout._();

  // 함수명: shouldUseLandscapeLayout
  // 역할:
  // - 화면 크기와 카메라 센서 방향을 함께 확인해 가로 촬영 화면 사용 여부를 결정한다.
  // - 화면 비율이 명확하면 화면 크기를 우선해 늦게 갱신된 센서 값이 배치를 뒤집지 않게 한다.
  // - 회전 중 화면이 정사각형에 가까운 짧은 구간에서만 센서 방향을 보조로 사용한다.
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
  // 역할: 가로 화면에서 미리보기와 조작 패널이 균형을 이루도록 패널 너비를 계산한다.
  static double landscapePanelWidth(Size viewportSize) {
    return (viewportSize.width * 0.30)
        .clamp(minimumLandscapePanelWidth, maximumLandscapePanelWidth)
        .toDouble();
  }

  static Rect guideRect(Size viewportSize) {
    if (viewportSize.isEmpty) {
      return Rect.zero;
    }

    final isLandscape = viewportSize.width > viewportSize.height;
    final maximumWidth = viewportSize.width * (isLandscape ? 0.84 : 0.86);
    final maximumHeight = viewportSize.height * (isLandscape ? 0.72 : 0.48);
    final widthFromHeight = maximumHeight * prescriptionAspectRatio;
    final guideWidth = math.min(maximumWidth, widthFromHeight);
    final guideHeight = guideWidth / prescriptionAspectRatio;
    final verticalOffset = isLandscape
        ? (viewportSize.height - guideHeight) / 2
        : math.max(20.0, (viewportSize.height - guideHeight) * 0.34);

    return Rect.fromLTWH(
      (viewportSize.width - guideWidth) / 2,
      verticalOffset,
      guideWidth,
      guideHeight,
    );
  }

  // 함수명: normalizedSourceRect
  // 함수역할:
  // - BoxFit.cover로 표시된 미리보기의 가이드 좌표를 원본 이미지의 0~1 좌표로 변환한다.
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
