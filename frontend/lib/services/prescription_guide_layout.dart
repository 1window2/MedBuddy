import 'dart:math' as math;

import 'package:flutter/material.dart';

// 파일명: prescription_guide_layout.dart
// 역할: 처방전 촬영 가이드와 실제 이미지 자르기가 공유할 좌표를 계산한다.

// 클래스명: PrescriptionGuideLayout
// 역할: 촬영 안내 영역과 실제 이미지 자르기가 공유하는 좌표 계산 경계이다.
// 주요 책임:
// - 화면 방향별 안내 배치를 계산하고 cover 미리보기의 가이드 영역을 원본 정규화 좌표로 역변환한다.
class PrescriptionGuideLayout {
  static const double prescriptionAspectRatio = 1.5;
  static const double landscapeGuideWidthFactor = 0.90;
  static const double landscapeGuideHeightFactor = 0.80;
  static const double minimumLandscapePanelWidth = 196;
  static const double maximumLandscapePanelWidth = 260;

  // 함수이름: PrescriptionGuideLayout._
  // 함수역할: 처방전 가이드의 공통 정적 비율·사각형 계산만 사용하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PrescriptionGuideLayout: 초기화된 인스턴스.
  const PrescriptionGuideLayout._();

  // 함수이름: shouldUseLandscapeLayout
  // 함수역할: 화면 크기와 카메라 센서 방향을 함께 확인해 가로 촬영 화면 사용 여부를 결정한다. 화면 비율이 명확하면 화면 크기를 우선해 늦게 갱신된 센서 값이 배치를 뒤집지 않게 한다. 회전 중 화면이 정사각형에 가까운 짧은 구간에서만 센서 방향을 보조로 사용한다.
  // 매개변수:
  // - viewportSize (Size): 촬영 미리보기를 배치할 화면 크기
  // - cameraReportsLandscape (bool): 회전 중 판단 보완에 사용할 카메라 가로 방향 보고값
  // 반환값:
  // - bool: 화면 크기와 카메라 센서 방향을 함께 확인해 가로 촬영 화면 사용 여부를 결정한다. 화면 비율이 명확하면 화면 크기를 우선해 늦게 갱신된 센서 값이 배치를 뒤집지 않게 한다. 회전 중 화면이 정사각형에 가까운 짧은 구간에서만 센서 방향을 보조로 사용한다.
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

  // 함수이름: landscapePanelWidth
  // 함수역할: 가로 화면에서 미리보기와 조작 패널이 균형을 이루도록 패널 너비를 계산한다.
  // 매개변수:
  // - viewportSize (Size): 촬영 미리보기를 배치할 화면 크기
  // 반환값:
  // - double: 가로 화면에서 미리보기와 조작 패널이 균형을 이루도록 패널 너비를 계산한다.
  static double landscapePanelWidth(Size viewportSize) {
    return (viewportSize.width * 0.30)
        .clamp(minimumLandscapePanelWidth, maximumLandscapePanelWidth)
        .toDouble();
  }

  // 함수이름: guideRect
  // 함수역할: 화면 방향별 최대 폭·높이와 처방전 비율 1.5를 적용해 가이드 사각형을 배치하고 빈 화면은 빈 영역으로 처리한다.
  // 매개변수:
  // - viewportSize (Size): 촬영 미리보기를 배치할 화면 크기
  // 반환값:
  // - Rect: 화면 방향별 최대 폭·높이와 처방전 비율 1.5를 적용해 가이드 사각형을 배치하고 빈 화면은 빈 영역으로 처리한다.
  static Rect guideRect(Size viewportSize) {
    if (viewportSize.isEmpty) {
      return Rect.zero;
    }

    final isLandscape = viewportSize.width > viewportSize.height;
    final maximumWidth =
        viewportSize.width * (isLandscape ? landscapeGuideWidthFactor : 0.86);
    final maximumHeight =
        viewportSize.height * (isLandscape ? landscapeGuideHeightFactor : 0.48);
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

  // 함수이름: normalizedSourceRect
  // 함수역할: BoxFit.cover로 표시된 미리보기의 가이드 좌표를 원본 이미지의 0~1 좌표로 변환한다.
  // 매개변수:
  // - viewportSize (Size): 촬영 미리보기를 배치할 화면 크기
  // - displayedImageSize (Size): 방향 보정 후 미리보기에 표시한 이미지 크기
  // - guideRect (Rect): 화면 미리보기에서 가이드가 차지하는 사각형
  // 반환값:
  // - Rect: BoxFit.cover로 표시된 미리보기의 가이드 좌표를 원본 이미지의 0~1 좌표로 변환한다.
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
