import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

import '../entities/prescription_camera_guide_entity.dart';

// 파일명: prescription_frame_analyzer.dart
// 역할: 카메라의 저해상도 밝기 정보를 이용해 처방전과 카메라 사이 거리를 추정한다.

// 클래스명: PrescriptionFrameAnalyzer
// 역할: 밝은 문서 영역의 크기와 위치를 분석해 촬영 거리 안내 상태를 계산한다.
// 주요 책임:
// - 카메라 원본 프레임을 작은 격자로 축소해 분석 비용을 제한한다.
// - 가장 큰 밝은 연결 영역을 처방전 후보로 선택한다.
// - 후보가 화면에서 차지하는 비율에 따라 가까이/적정/멀리 상태를 반환한다.
// 비고:
// - 거리 판정은 촬영을 제한하지 않는 보조 안내로만 사용한다.
class PrescriptionFrameAnalyzer {
  static const int _sampleWidth = 48;
  static const int _sampleHeight = 64;
  static const double _minimumDocumentCoverage = 0.18;
  static const double _maximumDocumentCoverage = 0.82;

  const PrescriptionFrameAnalyzer();

  // 함수이름: analyze
  // 함수역할:
  // - 카메라 밝기 평면에서 가장 큰 밝은 문서 후보를 찾고 촬영 거리를 판정한다.
  // 매개변수:
  // - luminanceBytes: 카메라 프레임의 밝기 평면 바이트
  // - width: 원본 프레임 너비
  // - height: 원본 프레임 높이
  // - bytesPerRow: 원본 프레임 한 행의 바이트 수
  // - bytesPerPixel: 밝기 픽셀 하나가 차지하는 바이트 수
  // 반환값:
  // - 문서 점유율과 거리 상태가 포함된 촬영 가이드 결과
  PrescriptionCameraGuideResult analyze({
    required Uint8List luminanceBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int bytesPerPixel,
    Rect normalizedRegion = const Rect.fromLTWH(0, 0, 1, 1),
    int rotationDegrees = 0,
  }) {
    if (luminanceBytes.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        bytesPerRow <= 0 ||
        bytesPerPixel <= 0) {
      return PrescriptionCameraGuideResult.searching;
    }

    final sample = _createLuminanceSample(
      luminanceBytes: luminanceBytes,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      bytesPerPixel: bytesPerPixel,
      normalizedRegion: normalizedRegion,
      rotationDegrees: rotationDegrees,
    );
    final range = _readLuminanceRange(sample);
    if (range.maximum - range.minimum < 24) {
      return PrescriptionCameraGuideResult.searching;
    }

    final threshold = _calculateOtsuThreshold(sample);
    final candidate = _findLargestBrightRegion(sample, threshold);
    if (candidate == null || candidate.pixelCoverage < 0.035) {
      return PrescriptionCameraGuideResult.searching;
    }

    final documentCoverage = candidate.boundingBoxCoverage;
    final analyzesGuideRegion =
        normalizedRegion.width < 0.99 || normalizedRegion.height < 0.99;
    final minimumCoverage = analyzesGuideRegion
        ? 0.24
        : _minimumDocumentCoverage;
    if (documentCoverage < minimumCoverage) {
      return PrescriptionCameraGuideResult(
        status: PrescriptionCameraGuideStatus.tooFar,
        documentCoverage: documentCoverage,
      );
    }
    final isTooClose = analyzesGuideRegion
        ? documentCoverage > 0.995 && candidate.pixelCoverage > 0.94
        : documentCoverage > _maximumDocumentCoverage ||
              candidate.touchedEdgeCount >= 3;
    if (isTooClose) {
      return PrescriptionCameraGuideResult(
        status: PrescriptionCameraGuideStatus.tooClose,
        documentCoverage: documentCoverage,
      );
    }

    return PrescriptionCameraGuideResult(
      status: PrescriptionCameraGuideStatus.aligned,
      documentCoverage: documentCoverage,
    );
  }

  Uint8List _createLuminanceSample({
    required Uint8List luminanceBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int bytesPerPixel,
    required Rect normalizedRegion,
    required int rotationDegrees,
  }) {
    final sample = Uint8List(_sampleWidth * _sampleHeight);
    for (var sampleY = 0; sampleY < _sampleHeight; sampleY += 1) {
      final normalizedY =
          normalizedRegion.top +
          normalizedRegion.height * sampleY / (_sampleHeight - 1);
      for (var sampleX = 0; sampleX < _sampleWidth; sampleX += 1) {
        final normalizedX =
            normalizedRegion.left +
            normalizedRegion.width * sampleX / (_sampleWidth - 1);
        final rawPosition = _mapDisplayedPointToRawFrame(
          normalizedX,
          normalizedY,
          rotationDegrees,
        );
        final sourceX = (rawPosition.dx * (width - 1)).round().clamp(
          0,
          width - 1,
        );
        final sourceY = (rawPosition.dy * (height - 1)).round().clamp(
          0,
          height - 1,
        );
        final sourceIndex = sourceY * bytesPerRow + sourceX * bytesPerPixel;
        if (sourceIndex < luminanceBytes.length) {
          sample[sampleY * _sampleWidth + sampleX] =
              luminanceBytes[sourceIndex];
        }
      }
    }
    return sample;
  }

  Offset _mapDisplayedPointToRawFrame(
    double displayedX,
    double displayedY,
    int rotationDegrees,
  ) {
    return switch (rotationDegrees % 360) {
      90 => Offset(displayedY, 1 - displayedX),
      180 => Offset(1 - displayedX, 1 - displayedY),
      270 => Offset(1 - displayedY, displayedX),
      _ => Offset(displayedX, displayedY),
    };
  }

  _LuminanceRange _readLuminanceRange(Uint8List sample) {
    var minimum = 255;
    var maximum = 0;
    for (final value in sample) {
      if (value < minimum) {
        minimum = value;
      }
      if (value > maximum) {
        maximum = value;
      }
    }
    return _LuminanceRange(minimum: minimum, maximum: maximum);
  }

  int _calculateOtsuThreshold(Uint8List sample) {
    final histogram = List<int>.filled(256, 0);
    for (final value in sample) {
      histogram[value] += 1;
    }

    var totalBrightness = 0.0;
    for (var value = 0; value < histogram.length; value += 1) {
      totalBrightness += value * histogram[value];
    }

    var backgroundWeight = 0;
    var backgroundBrightness = 0.0;
    var maximumVariance = -1.0;
    var threshold = 128;
    for (var value = 0; value < histogram.length; value += 1) {
      backgroundWeight += histogram[value];
      if (backgroundWeight == 0) {
        continue;
      }
      final foregroundWeight = sample.length - backgroundWeight;
      if (foregroundWeight == 0) {
        break;
      }

      backgroundBrightness += value * histogram[value];
      final backgroundMean = backgroundBrightness / backgroundWeight;
      final foregroundMean =
          (totalBrightness - backgroundBrightness) / foregroundWeight;
      final difference = backgroundMean - foregroundMean;
      final variance =
          backgroundWeight * foregroundWeight * difference * difference;
      if (variance > maximumVariance) {
        maximumVariance = variance;
        threshold = value;
      }
    }
    return threshold.clamp(90, 220);
  }

  _BrightRegion? _findLargestBrightRegion(Uint8List sample, int threshold) {
    final visited = Uint8List(sample.length);
    _BrightRegion? largestRegion;

    for (var startIndex = 0; startIndex < sample.length; startIndex += 1) {
      if (visited[startIndex] == 1 || sample[startIndex] <= threshold) {
        continue;
      }
      final region = _collectBrightRegion(
        sample: sample,
        visited: visited,
        startIndex: startIndex,
        threshold: threshold,
      );
      if (largestRegion == null ||
          region.pixelCount > largestRegion.pixelCount) {
        largestRegion = region;
      }
    }
    return largestRegion;
  }

  _BrightRegion _collectBrightRegion({
    required Uint8List sample,
    required Uint8List visited,
    required int startIndex,
    required int threshold,
  }) {
    final pendingIndexes = Queue<int>()..add(startIndex);
    visited[startIndex] = 1;
    var pixelCount = 0;
    var minimumX = _sampleWidth;
    var maximumX = 0;
    var minimumY = _sampleHeight;
    var maximumY = 0;

    while (pendingIndexes.isNotEmpty) {
      final index = pendingIndexes.removeFirst();
      final x = index % _sampleWidth;
      final y = index ~/ _sampleWidth;
      pixelCount += 1;
      minimumX = x < minimumX ? x : minimumX;
      maximumX = x > maximumX ? x : maximumX;
      minimumY = y < minimumY ? y : minimumY;
      maximumY = y > maximumY ? y : maximumY;

      _visitNeighbor(
        sample: sample,
        visited: visited,
        pendingIndexes: pendingIndexes,
        x: x - 1,
        y: y,
        threshold: threshold,
      );
      _visitNeighbor(
        sample: sample,
        visited: visited,
        pendingIndexes: pendingIndexes,
        x: x + 1,
        y: y,
        threshold: threshold,
      );
      _visitNeighbor(
        sample: sample,
        visited: visited,
        pendingIndexes: pendingIndexes,
        x: x,
        y: y - 1,
        threshold: threshold,
      );
      _visitNeighbor(
        sample: sample,
        visited: visited,
        pendingIndexes: pendingIndexes,
        x: x,
        y: y + 1,
        threshold: threshold,
      );
    }

    return _BrightRegion(
      pixelCount: pixelCount,
      minimumX: minimumX,
      maximumX: maximumX,
      minimumY: minimumY,
      maximumY: maximumY,
    );
  }

  void _visitNeighbor({
    required Uint8List sample,
    required Uint8List visited,
    required Queue<int> pendingIndexes,
    required int x,
    required int y,
    required int threshold,
  }) {
    if (x < 0 || x >= _sampleWidth || y < 0 || y >= _sampleHeight) {
      return;
    }
    final index = y * _sampleWidth + x;
    if (visited[index] == 1 || sample[index] <= threshold) {
      return;
    }
    visited[index] = 1;
    pendingIndexes.add(index);
  }
}

class _LuminanceRange {
  final int minimum;
  final int maximum;

  const _LuminanceRange({required this.minimum, required this.maximum});
}

class _BrightRegion {
  final int pixelCount;
  final int minimumX;
  final int maximumX;
  final int minimumY;
  final int maximumY;

  const _BrightRegion({
    required this.pixelCount,
    required this.minimumX,
    required this.maximumX,
    required this.minimumY,
    required this.maximumY,
  });

  double get pixelCoverage =>
      pixelCount /
      (PrescriptionFrameAnalyzer._sampleWidth *
          PrescriptionFrameAnalyzer._sampleHeight);

  double get boundingBoxCoverage {
    final width = maximumX - minimumX + 1;
    final height = maximumY - minimumY + 1;
    return width *
        height /
        (PrescriptionFrameAnalyzer._sampleWidth *
            PrescriptionFrameAnalyzer._sampleHeight);
  }

  int get touchedEdgeCount {
    var count = 0;
    if (minimumX == 0) {
      count += 1;
    }
    if (maximumX == PrescriptionFrameAnalyzer._sampleWidth - 1) {
      count += 1;
    }
    if (minimumY == 0) {
      count += 1;
    }
    if (maximumY == PrescriptionFrameAnalyzer._sampleHeight - 1) {
      count += 1;
    }
    return count;
  }
}
