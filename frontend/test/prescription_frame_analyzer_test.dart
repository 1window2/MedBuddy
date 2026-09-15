// 파일명: prescription_frame_analyzer_test.dart
// 역할: 처방전 촬영 거리 판정 서비스의 경계 조건을 검증한다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/prescription_camera_guide_entity.dart';
import 'package:medbuddy_frontend/services/prescription_frame_analyzer.dart';


// 함수이름: main
// 함수역할:
// - 처방전 프레임 탐지와 거리 판정 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  const analyzer = PrescriptionFrameAnalyzer();

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 작은 처방전 후보는 카메라에서 너무 먼 상태로 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 가이드 영역에 맞는 처방전 후보는 적정 거리로 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 화면을 대부분 채운 처방전 후보는 너무 가까운 상태로 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 밝기 차이가 없는 프레임은 처방전을 찾는 상태를 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('밝기 차이가 없는 프레임은 처방전을 찾는 상태를 유지한다', () {
    final frame = Uint8List(_frameWidth * _frameHeight)
      ..fillRange(0, _frameWidth * _frameHeight, 120);

    final result = _analyzeFrame(analyzer, frame);

    expect(result.status, PrescriptionCameraGuideStatus.searching);
  });
}

const int _frameWidth = 480;
const int _frameHeight = 640;

// 함수이름: _analyzeFrame
// 함수역할:
// - 고정 프레임 크기와 한 픽셀당 한 바이트 휘도 형식으로 거리 분석을 요청한다.
// 매개변수:
// - analyzer (PrescriptionFrameAnalyzer): 검사할 프레임 거리 분석기.
// - frame (Uint8List): 거리 판정에 사용할 회색조 프레임 바이트.
// 반환값:
// - 처방전 탐지 여부와 거리 안내 결과.
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

// 함수이름: _createFrameWithDocument
// 함수역할:
// - 어두운 배경에 지정 사각형만 밝게 채워 처방전 크기별 합성 휘도 프레임을 만든다.
// 매개변수:
// - left (int): 밝은 문서 사각형의 포함되는 왼쪽 열 경계.
// - top (int): 밝은 문서 사각형의 포함되는 위쪽 행 경계.
// - right (int): 밝은 문서 사각형의 제외되는 오른쪽 열 경계.
// - bottom (int): 밝은 문서 사각형의 제외되는 아래쪽 행 경계.
// 반환값:
// - 배경 밝기 35와 문서 밝기 230의 프레임 바이트.
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
