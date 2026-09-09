// 파일명: pill_image_crop_service.dart
// 역할: 원본 해상도와 방향을 보존하며 식별된 알약 영역만 메모리에서 추출한다.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../entities/pill_identification_entity.dart';

// 클래스명: PillImageCropService
// 역할: UI 스레드 밖에서 검증된 영역을 자르고 디스크에는 사진을 저장하지 않는다.
class PillImageCropService {
  // 함수이름: PillImageCropService
  // 함수역할: 상태 없는 영역 추출기를 만든다. 매개변수: 없음. 반환값: 서비스.
  const PillImageCropService();

  // 함수이름: cropRegion
  // 함수역할: 바이트·픽셀 상한과 영역을 검증한 뒤 별도 isolate에서 자른다.
  // 매개변수: image는 원본 사진, region은 EXIF 보정 후 기준의 정규화 영역이다.
  // 반환값: 해당 알약의 JPEG 바이트. 잘못된 사진·좌표는 FormatException.
  Future<Uint8List> cropRegion(Uint8List image, PillBoundingBox region) =>
      compute(_cropRegion, (image, region));
}

// 함수이름: _cropRegion
// 함수역할: 원본 픽셀을 먼저 잘라 작은 알약의 세부 정보가 전체 축소로 사라지지 않게 한다.
// 매개변수: input은 원본 사진과 정규화 영역이다.
// 반환값: 최대 1600픽셀의 JPEG. 빈 파일·과대 이미지·잘못된 영역은 거부한다.
Uint8List _cropRegion((Uint8List, PillBoundingBox) input) {
  final (bytes, box) = input;
  if (bytes.length < 16 || bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Invalid pill image size.');
  }
  PillBoundingBox.fromJson({
    'left': box.left,
    'top': box.top,
    'width': box.width,
    'height': box.height,
  });
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 24000000) {
    throw const FormatException('Invalid pill image dimensions.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Unreadable pill image.');
  final source = img.bakeOrientation(decoded);
  final left = (box.left * source.width).floor().clamp(0, source.width - 1);
  final top = (box.top * source.height).floor().clamp(0, source.height - 1);
  final right = ((box.left + box.width) * source.width).ceil().clamp(
    left + 1,
    source.width,
  );
  final bottom = ((box.top + box.height) * source.height).ceil().clamp(
    top + 1,
    source.height,
  );
  if (right - left < 16 || bottom - top < 16) {
    throw const FormatException('Pill region is too small.');
  }
  var crop = img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  if (math.max(crop.width, crop.height) > 1600) {
    crop = img.copyResize(
      crop,
      width: crop.width >= crop.height ? 1600 : null,
      height: crop.height > crop.width ? 1600 : null,
      interpolation: img.Interpolation.average,
    );
  }
  // 최소 입력 크기는 흰 여백으로 충족하며 각인 생성이나 픽셀 확대는 하지 않는다.
  final canvas = img.Image(
    width: math.max(128, crop.width + 16),
    height: math.max(128, crop.height + 16),
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(
    canvas,
    crop,
    dstX: (canvas.width - crop.width) ~/ 2,
    dstY: (canvas.height - crop.height) ~/ 2,
  );
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 95));
}
