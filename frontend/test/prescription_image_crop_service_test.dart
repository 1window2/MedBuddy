// 파일명: prescription_image_crop_service_test.dart
// 역할: 촬영 가이드 영역과 실제 이미지 좌표의 변환 및 자르기를 검증한다.

import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_library;
import 'package:medbuddy_frontend/services/prescription_image_crop_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Class Name: _TemporaryPathProvider
// Role: Reports a test directory as the app temporary directory.
// Responsibilities:
// - Let the stale guide-crop cleanup run against a sandbox instead of the platform cache directory.
// Attributes:
// - temporaryPath (String): Directory returned as the app temporary directory.
class _TemporaryPathProvider extends PathProviderPlatform {
  final String temporaryPath;

  // Function Name: _TemporaryPathProvider
  // Description:
  // - Store the directory to report.
  // Parameters:
  // - temporaryPath (String): Directory returned as the app temporary directory.
  // Returns:
  // - A path provider fake.
  _TemporaryPathProvider(this.temporaryPath);

  // Function Name: getTemporaryPath
  // Description:
  // - Return the configured directory.
  // Parameters:
  // - None.
  // Returns:
  // - The configured temporary directory path.
  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

// Function Name: main
// Description:
// - Register regression cases for prescription image cropping and sensitive-original deletion on
//   failures.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 정규화된 가이드 좌표만 잘라 새 이미지로 저장한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('정규화된 가이드 좌표만 잘라 새 이미지로 저장한다', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-crop-',
    );
    // 함수이름: addTearDown 콜백
    // 함수역할:
    // - 실패 경로를 포함해 사례 종료 후 임시 이미지 폴더를 정리한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 임시 파일 정리 완료.
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

  // Function Name: test callback
  // Description:
  // - Verify that image decoding failure still deletes the sensitive captured original.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('이미지 해석에 실패해도 민감한 촬영 원본을 삭제한다', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-crop-failure-',
    );
    // 함수이름: addTearDown 콜백
    // 함수역할:
    // - 실패 경로를 포함해 사례 종료 후 임시 이미지 폴더를 정리한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 임시 파일 정리 완료.
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

  // Function Name: test callback
  // Description:
  // - Verify that failure to write the cropped image still deletes the captured original.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('파생 이미지 쓰기에 실패해도 촬영 원본을 삭제한다', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-write-failure-',
    );
    // 함수이름: addTearDown 콜백
    // 함수역할:
    // - 실패 경로를 포함해 사례 종료 후 임시 이미지 폴더를 정리한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 임시 파일 정리 완료.
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

  // Function Name: test callback
  // Description:
  // - Verify that the stale-crop cleanup removes only guide crops older than one day from the app temporary directory and leaves recent crops, other files and subdirectories alone.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('하루가 지난 가이드 촬영본만 임시 폴더에서 정리한다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-prescription-stale-guide-',
    );
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(
      temporaryDirectory.path,
    );
    // Function Name: addTearDown callback
    // Description:
    // - Restore the path provider and remove the sandbox after the case, including failure paths.
    // Parameters:
    // - None.
    // Returns:
    // - Completion of temporary-file cleanup.
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      await temporaryDirectory.delete(recursive: true);
    });
    final now = DateTime(2026, 9, 10, 12);
    final staleGuide = File('${temporaryDirectory.path}/CAP1_guide.jpg');
    final recentGuide = File('${temporaryDirectory.path}/CAP2_guide.jpg');
    final staleOtherFile = File('${temporaryDirectory.path}/scaled_photo.jpg');
    final nestedDirectory = await Directory(
      '${temporaryDirectory.path}/nested_guide.jpg',
    ).create();
    for (final file in [staleGuide, recentGuide, staleOtherFile]) {
      await file.writeAsBytes([1, 2, 3]);
    }
    await staleGuide.setLastModified(now.subtract(const Duration(days: 2)));
    await recentGuide.setLastModified(now.subtract(const Duration(hours: 23)));
    await staleOtherFile.setLastModified(
      now.subtract(const Duration(days: 2)),
    );

    const service = PrescriptionImageCropService();
    final deletedCount = await service.deleteStaleGuideImages(now: now);

    expect(deletedCount, 1);
    expect(await staleGuide.exists(), isFalse);
    expect(await recentGuide.exists(), isTrue);
    expect(await staleOtherFile.exists(), isTrue);
    expect(await nestedDirectory.exists(), isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Verify that the stale-crop cleanup reports nothing instead of throwing when the temporary directory cannot be resolved.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('임시 폴더를 알 수 없으면 가이드 촬영본 정리를 건너뛴다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(
      '${Directory.systemTemp.path}/medbuddy-missing-temporary-directory',
    );
    // Function Name: addTearDown callback
    // Description:
    // - Restore the path provider after the case.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the original provider is restored.
    addTearDown(() => PathProviderPlatform.instance = originalProvider);

    const service = PrescriptionImageCropService();

    expect(await service.deleteStaleGuideImages(), 0);
  });
}
