// 파일명: prescription_image_crop_service_test.dart
// 역할: 촬영 결과가 화면 가이드에 해당하는 영역만 남기는지 검증한다.

import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_library;
import 'package:medbuddy_frontend/services/prescription_image_crop_service.dart';

void main() {
  test('정규화된 가이드 좌표만 잘라 새 이미지로 저장한다', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-crop-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final sourceFile = File('${temporaryDirectory.path}/source.png');
    final sourceImage = image_library.Image(width: 200, height: 100);
    await sourceFile.writeAsBytes(image_library.encodePng(sourceImage));

    const service = PrescriptionImageCropService();
    final result = await service.cropToGuide(
      sourceImage: XFile(sourceFile.path),
      normalizedGuideRect: const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8),
    );
    final croppedImage = image_library.decodeImage(
      await File(result.path).readAsBytes(),
    );

    expect(croppedImage, isNotNull);
    expect(croppedImage!.width, 100);
    expect(croppedImage.height, 60);
    expect(await sourceFile.exists(), isFalse);
    expect(await File(result.path).exists(), isTrue);
  });

  test('이미지 해석에 실패해도 민감한 촬영 원본을 삭제한다', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-crop-failure-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final sourceFile = File('${temporaryDirectory.path}/source.jpg');
    await sourceFile.writeAsBytes([0, 1, 2, 3]);

    const service = PrescriptionImageCropService();

    await expectLater(
      service.cropToGuide(
        sourceImage: XFile(sourceFile.path),
        normalizedGuideRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      ),
      throwsA(anything),
    );
    expect(await sourceFile.exists(), isFalse);
    expect(
      await File('${temporaryDirectory.path}/source_guide.jpg').exists(),
      isFalse,
    );
  });

  test('파생 이미지 쓰기에 실패해도 촬영 원본을 삭제한다', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-write-failure-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final sourceFile = File('${temporaryDirectory.path}/source.png');
    final sourceImage = image_library.Image(width: 20, height: 20);
    await sourceFile.writeAsBytes(image_library.encodePng(sourceImage));
    await Directory('${temporaryDirectory.path}/source_guide.jpg').create();

    const service = PrescriptionImageCropService();

    await expectLater(
      service.cropToGuide(
        sourceImage: XFile(sourceFile.path),
        normalizedGuideRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await sourceFile.exists(), isFalse);
  });
}
