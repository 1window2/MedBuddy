import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as image_library;

// 파일명: prescription_image_crop_service.dart
// 역할: 촬영한 원본 사진에서 화면 가이드 안쪽만 남긴 OCR 입력 이미지를 만든다.

// 클래스명: PrescriptionImageCropService
// 역할: EXIF 방향을 반영한 뒤 정규화된 가이드 좌표로 이미지를 안전하게 자른다.
class PrescriptionImageCropService {
  const PrescriptionImageCropService();

  // 함수명: cropToGuide
  // 역할: 촬영 원본을 올바른 방향으로 회전한 뒤 가이드 영역만 JPEG로 저장한다.
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

  // 함수명: _deleteIfPresent
  // 역할:
  // - 촬영 원본 또는 실패 중 생성된 파생 파일을 존재할 때만 삭제한다.
  // - 주 처리 오류를 보존해야 하는 롤백 경로에서는 삭제 오류를 선택적으로 무시한다.
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
