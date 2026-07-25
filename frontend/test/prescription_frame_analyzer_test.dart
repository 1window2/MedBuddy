import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/prescription_camera_guide_entity.dart';
import 'package:medbuddy_frontend/services/prescription_frame_analyzer.dart';

// 파일명: prescription_frame_analyzer_test.dart
// 역할: 처방전 촬영 거리 판정 서비스의 경계 조건을 검증한다.

void main() {
  const analyzer = PrescriptionFrameAnalyzer();

  test('작은 처방전 후보는 카메라에서 너무 먼 상태로 판정한다', () {
    final frame = _createFrameWithDocument(
      left: 180,
      top: 250,
      right: 300,
      bottom: 390,
    );

    final result = _analyzeFrame(analyzer, frame);

    expect(result.status, PrescriptionCameraGuideStatus.tooFar);
  });

  test('가이드 영역에 맞는 처방전 후보는 적정 거리로 판정한다', () {
    final frame = _createFrameWithDocument(
      left: 100,
      top: 110,
      right: 380,
      bottom: 530,
    );

    final result = _analyzeFrame(analyzer, frame);

    expect(result.status, PrescriptionCameraGuideStatus.aligned);
  });

  test('화면을 대부분 채운 처방전 후보는 너무 가까운 상태로 판정한다', () {
    final frame = _createFrameWithDocument(
      left: 4,
      top: 4,
      right: 476,
      bottom: 636,
    );

    final result = _analyzeFrame(analyzer, frame);

    expect(result.status, PrescriptionCameraGuideStatus.tooClose);
  });

  test('밝기 차이가 없는 프레임은 처방전을 찾는 상태를 유지한다', () {
    final frame = Uint8List(_frameWidth * _frameHeight)
      ..fillRange(0, _frameWidth * _frameHeight, 120);

    final result = _analyzeFrame(analyzer, frame);

    expect(result.status, PrescriptionCameraGuideStatus.searching);
  });
}

const int _frameWidth = 480;
const int _frameHeight = 640;

PrescriptionCameraGuideResult _analyzeFrame(
  PrescriptionFrameAnalyzer analyzer,
  Uint8List frame,
) {
  return analyzer.analyze(
    luminanceBytes: frame,
    width: _frameWidth,
    height: _frameHeight,
    bytesPerRow: _frameWidth,
    bytesPerPixel: 1,
  );
}

Uint8List _createFrameWithDocument({
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final frame = Uint8List(_frameWidth * _frameHeight)
    ..fillRange(0, _frameWidth * _frameHeight, 35);
  for (var y = top; y < bottom; y += 1) {
    final rowStart = y * _frameWidth;
    frame.fillRange(rowStart + left, rowStart + right, 230);
  }
  return frame;
}
