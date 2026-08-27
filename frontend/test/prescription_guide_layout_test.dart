// 파일명: prescription_guide_layout_test.dart
// 역할: 화면 회전에 따른 처방전 가이드와 원본 이미지 자르기 좌표를 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_guide_layout.dart';

void main() {
  test('명확한 화면 비율은 늦게 갱신된 카메라 방향보다 우선한다', () {
    expect(
      PrescriptionGuideLayout.shouldUseLandscapeLayout(
        viewportSize: const Size(700, 390),
      ),
      isTrue,
    );
    expect(
      PrescriptionGuideLayout.shouldUseLandscapeLayout(
        viewportSize: const Size(390, 700),
        cameraReportsLandscape: true,
      ),
      isFalse,
    );
    expect(
      PrescriptionGuideLayout.shouldUseLandscapeLayout(
        viewportSize: const Size(390, 700),
      ),
      isFalse,
    );
  });

  test('회전 중 화면 비율이 비슷할 때만 카메라 방향을 보조로 사용한다', () {
    expect(
      PrescriptionGuideLayout.shouldUseLandscapeLayout(
        viewportSize: const Size(410, 400),
        cameraReportsLandscape: true,
      ),
      isTrue,
    );
    expect(
      PrescriptionGuideLayout.shouldUseLandscapeLayout(
        viewportSize: const Size(400, 410),
      ),
      isFalse,
    );
  });

  test('가로 조작 패널은 미리보기 공간을 침범하지 않도록 너비를 제한한다', () {
    expect(
      PrescriptionGuideLayout.landscapePanelWidth(const Size(600, 300)),
      PrescriptionGuideLayout.minimumLandscapePanelWidth,
    );
    expect(
      PrescriptionGuideLayout.landscapePanelWidth(const Size(1200, 600)),
      PrescriptionGuideLayout.maximumLandscapePanelWidth,
    );
  });

  test('세로와 가로 화면 모두 가이드가 미리보기 안에 유지된다', () {
    const portraitSize = Size(390, 700);
    const landscapeSize = Size(700, 390);

    final portraitGuide = PrescriptionGuideLayout.guideRect(portraitSize);
    final landscapeGuide = PrescriptionGuideLayout.guideRect(landscapeSize);

    expect(
      (Offset.zero & portraitSize).contains(portraitGuide.topLeft),
      isTrue,
    );
    expect(
      (Offset.zero & portraitSize).contains(portraitGuide.bottomRight),
      isTrue,
    );
    expect(
      (Offset.zero & landscapeSize).contains(landscapeGuide.topLeft),
      isTrue,
    );
    expect(
      (Offset.zero & landscapeSize).contains(landscapeGuide.bottomRight),
      isTrue,
    );
    expect(landscapeGuide.width, greaterThan(landscapeGuide.height));
    expect(
      landscapeGuide.height,
      closeTo(
        landscapeSize.height *
            PrescriptionGuideLayout.landscapeGuideHeightFactor,
        0.001,
      ),
    );
    expect(
      landscapeGuide.width / landscapeGuide.height,
      closeTo(PrescriptionGuideLayout.prescriptionAspectRatio, 0.001),
    );
  });

  test('화면 가이드를 BoxFit cover 원본 이미지의 정규화 좌표로 변환한다', () {
    const viewportSize = Size(400, 600);
    const sourceSize = Size(1600, 900);
    final guideRect = PrescriptionGuideLayout.guideRect(viewportSize);

    final normalizedRect = PrescriptionGuideLayout.normalizedSourceRect(
      viewportSize: viewportSize,
      displayedImageSize: sourceSize,
      guideRect: guideRect,
    );

    expect(normalizedRect.left, inInclusiveRange(0, 1));
    expect(normalizedRect.top, inInclusiveRange(0, 1));
    expect(normalizedRect.right, inInclusiveRange(0, 1));
    expect(normalizedRect.bottom, inInclusiveRange(0, 1));
    expect(normalizedRect.width, lessThan(1));
    expect(normalizedRect.height, lessThan(1));
  });
}
