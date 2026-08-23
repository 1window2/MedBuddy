import 'dart:math' as math;

import 'package:flutter/material.dart';

// 파일명: prescription_guide_layout.dart
// 역할: 처방전 촬영 가이드와 실제 이미지 자르기가 공유할 좌표를 계산한다.

// 클래스명: PrescriptionGuideLayout
// 역할: 세로·가로 화면에 맞는 가이드 영역과 원본 이미지 기준 자르기 비율을 제공한다.
class PrescriptionGuideLayout {
  static const double prescriptionAspectRatio = 1.5;

  const PrescriptionGuideLayout._();

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
