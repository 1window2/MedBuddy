import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as image_library;

// 파일명: prescription_image_crop_service.dart
// 역할: 촬영한 원본 사진에서 화면 가이드 안쪽만 남긴 OCR 입력 이미지를 만든다.

// Class Name: PrescriptionImageCropService
// Role: Produces OCR input by cropping the captured image to the displayed prescription guide.
// Responsibilities:
// - Apply EXIF orientation, clamp crop coordinates, write the derived JPEG, and attempt cleanup of raw captures and failed partial outputs.
class PrescriptionImageCropService {
  // 함수이름: PrescriptionImageCropService
  // 함수역할: 촬영 파일의 방향 보정·가이드 자르기 및 원본 정리를 수행할 무상태 서비스를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PrescriptionImageCropService: 초기화된 인스턴스.
  const PrescriptionImageCropService();

  // Function Name: cropToGuide
  // Description: Applies EXIF orientation and writes the bounded guide crop as JPEG. Always attempts raw-capture cleanup and attempts to remove the derived output if processing or raw cleanup fails.
  // Parameters:
  // - sourceImage (XFile): App-owned raw capture to crop to the guide.
  // - normalizedGuideRect (Rect): Normalized zero-to-one crop region of the orientation-corrected image consumed by this service.
  // Returns:
  // - Future<XFile>: the derived guide JPEG after successful raw-capture cleanup; processing and nonsuppressed cleanup errors propagate.
  Future<XFile> cropToGuide({
    required XFile sourceImage,
    required Rect normalizedGuideRect,
  }) async {
    final sourceFile = File(sourceImage.path);
    File? croppedFile;
    try {
      final decodedImage = image_library.decodeImage(
        await sourceFile.readAsBytes(),
      );
      if (decodedImage == null) {
        throw const FormatException('촬영한 처방전 이미지를 읽을 수 없습니다.');
      }

      final orientedImage = image_library.bakeOrientation(decodedImage);
      final cropRect = _pixelCropRect(
        normalizedGuideRect,
        orientedImage.width,
        orientedImage.height,
      );
      final croppedImage = image_library.copyCrop(
        orientedImage,
        x: cropRect.left.toInt(),
        y: cropRect.top.toInt(),
        width: cropRect.width.toInt(),
        height: cropRect.height.toInt(),
      );
      final sourceName = sourceFile.uri.pathSegments.last;
      final sourceBaseName = sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '');
      croppedFile = File(
        '${sourceFile.parent.path}${Platform.pathSeparator}'
        '${sourceBaseName}_guide.jpg',
      );
      await croppedFile.writeAsBytes(
        image_library.encodeJpg(croppedImage, quality: 92),
        flush: true,
      );
    } catch (_) {
      await _deleteIfPresent(croppedFile, ignoreErrors: true);
      rethrow;
    } finally {
      try {
        await _deleteIfPresent(sourceFile);
      } catch (_) {
        await _deleteIfPresent(croppedFile, ignoreErrors: true);
        rethrow;
      }
    }
    return XFile(croppedFile.path);
  }

  // Function Name: _deleteIfPresent
  // Description: Deletes a capture or partial output only when present, optionally suppressing cleanup errors so the original processing failure is preserved.
  // Parameters:
  // - file (File?): Capture or derived file to remove when present.
  // - ignoreErrors (bool): Whether cleanup errors should be suppressed to preserve the original failure.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _deleteIfPresent(File? file, {bool ignoreErrors = false}) async {
    if (file == null) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      if (!ignoreErrors) {
        rethrow;
      }
    }
  }

  // 함수이름: _pixelCropRect
  // 함수역할: 정규화 경계를 0~1로 제한하고 바깥쪽으로 픽셀 반올림해 이미지 내부의 최소 1픽셀 자르기 영역을 만든다.
  // 매개변수:
  // - normalizedRect (Rect): 방향 보정된 이미지에서 자를 영역의 0~1 정규화 좌표
  // - width (int): 원본 이미지의 너비(픽셀)
  // - height (int): 원본 이미지의 높이(픽셀)
  // 반환값:
  // - Rect: 이미지 픽셀 경계 안에 제한된 자르기 사각형으로, 너비와 높이가 각각 최소 1픽셀이다.
  Rect _pixelCropRect(Rect normalizedRect, int width, int height) {
    final safeRect = Rect.fromLTRB(
      normalizedRect.left.clamp(0.0, 1.0),
      normalizedRect.top.clamp(0.0, 1.0),
      normalizedRect.right.clamp(0.0, 1.0),
      normalizedRect.bottom.clamp(0.0, 1.0),
    );
    final left = (safeRect.left * width).floor().clamp(0, width - 1);
    final top = (safeRect.top * height).floor().clamp(0, height - 1);
    final right = (safeRect.right * width).ceil().clamp(left + 1, width);
    final bottom = (safeRect.bottom * height).ceil().clamp(top + 1, height);
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }
}
