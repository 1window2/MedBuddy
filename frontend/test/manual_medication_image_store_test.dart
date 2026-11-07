// 파일명: manual_medication_image_store_test.dart
// 역할: 직접 등록 사진의 백그라운드 압축과 계정별 저장을 검증한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';

// 클래스명: _ImagePaths
// 역할: 직접 등록 사진의 영속 저장 루트를 독립 테스트 폴더로 교체한다.
// 주요 책임:
// - 실제 플랫폼 경로에 접근하지 않고 지정한 지원 디렉터리를 반환한다.
// 속성:
// - root(String): 테스트가 생성하고 정리하는 저장 루트 경로.
class _ImagePaths extends PathProviderPlatform {
  final String root;
  // 함수이름: _ImagePaths
  // 함수역할:
  // - 이미지 저장소에 노출할 지원 디렉터리 경로를 보관한다.
  // 매개변수:
  // - root(String): 생성해 둔 테스트 폴더 경로.
  // 반환값:
  // - _ImagePaths: 실제 플랫폼 경로 조회를 대체할 제공자.
  _ImagePaths(this.root);
  // 함수이름: getApplicationSupportPath
  // 함수역할:
  // - 사용자 데이터 폴더 대신 테스트 루트를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<String?>: 항상 지정한 root 값; 디렉터리 존재 여부는 확인하지 않는다.
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

// 함수이름: main
// 함수역할:
// - 사진 크기 제한, 고아 사진 정리 경합과 새 약 ID로의 복사 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: test callback
  // 함수역할:
  // - 2000×1000 PNG를 원본 보존 상태로 1600×800 JPEG에 저장하고 다른 계정은 찾지 못하며 잘못된 이미지 입력은 파일을 남기지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('큰 사진은 비율을 유지하고 사용자별 1600px JPEG로 저장한다', () async {
    final directory = await Directory.systemTemp.createTemp('medbuddy-photo-test-');
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _ImagePaths(directory.path);
    try {
      final source = File('${directory.path}/source.png');
      await source.writeAsBytes(img.encodePng(img.Image(width: 2000, height: 1000)));
      const store = ManualMedicationImageStore();
      final path = await store.saveImage(patientHash: 'patient-a', medicationId: 1,
          sourcePath: source.path);
      final result = img.decodeJpg(await File(path).readAsBytes())!;
      expect(result.width, 1600);
      expect(result.height, 800);
      expect(await source.exists(), isTrue);
      expect(await store.findImagePath(patientHash: 'patient-b', medicationId: 1), '');
      final bad = File('${directory.path}/bad.jpg');
      await bad.writeAsString('not an image');
      await expectLater(store.saveImage(patientHash: 'patient-a', medicationId: 2,
          sourcePath: bad.path), throwsFormatException);
      expect(await store.findImagePath(patientHash: 'patient-a', medicationId: 2), '');
    } finally {
      PathProviderPlatform.instance = originalProvider;
      await directory.delete(recursive: true);
    }
  });

  // 늦게 끝난 목록 조회는 조회 시작 뒤 저장한 새 약 사진을 고아로 지우지 않는다.
  // Function Name: test callback
  // Description:
  // - Remove only photos older than the list request boundary; a newly saved image survives that stale cleanup but is removable without the boundary.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('목록 조회 시작 뒤 저장한 사진은 고아 사진 정리에서 남긴다', () async {
    final directory = await Directory.systemTemp.createTemp('medbuddy-photo-orphan-');
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _ImagePaths(directory.path);
    try {
      final source = File('${directory.path}/source.png');
      await source.writeAsBytes(img.encodePng(img.Image(width: 20, height: 10)));
      const store = ManualMedicationImageStore();
      final old = await store.saveImage(patientHash: 'patient-a', medicationId: 1,
          sourcePath: source.path);
      await File(old).setLastModified(DateTime.now().subtract(const Duration(minutes: 5)));
      final listRequestedAt = DateTime.now().subtract(const Duration(seconds: 1));
      final fresh = await store.saveImage(patientHash: 'patient-a', medicationId: 2,
          sourcePath: source.path);
      await store.removeOrphanImages(patientHash: 'patient-a', activeMedicationIds: {},
          keepWrittenAfter: listRequestedAt);
      expect(await File(old).exists(), isFalse);
      expect(await File(fresh).exists(), isTrue);
      await store.removeOrphanImages(patientHash: 'patient-a', activeMedicationIds: {});
      expect(await File(fresh).exists(), isFalse);
    } finally {
      PathProviderPlatform.instance = originalProvider;
      await directory.delete(recursive: true);
    }
  });

  // 처방 변경으로 새 ID가 생겨도 기기 사진이 새 항목에 이어지고 이전 기록 행의 사진은 남는다.
  // Function Name: test callback
  // Description:
  // - Copy the original bytes to a new medication ID without removing the old photo; copying from a nonexistent source must not create a destination image.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('처방 변경의 새 약 ID로 사진을 복사하고 이전 사진과 기존 사진을 유지한다', () async {
    final directory = await Directory.systemTemp.createTemp('medbuddy-photo-copy-');
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _ImagePaths(directory.path);
    try {
      final source = File('${directory.path}/source.png');
      await source.writeAsBytes(img.encodePng(img.Image(width: 20, height: 10)));
      const store = ManualMedicationImageStore();
      final original = await store.saveImage(patientHash: 'patient-a', medicationId: 7,
          sourcePath: source.path);
      await store.copyImage(patientHash: 'patient-a', fromMedicationId: 7, toMedicationId: 8);
      final copied = await store.findImagePath(patientHash: 'patient-a', medicationId: 8);
      expect(copied, isNotEmpty);
      expect(await File(copied).readAsBytes(), await File(original).readAsBytes());
      expect(await store.findImagePath(patientHash: 'patient-a', medicationId: 7), original);
      await store.copyImage(patientHash: 'patient-a', fromMedicationId: 1, toMedicationId: 9);
      expect(await store.findImagePath(patientHash: 'patient-a', medicationId: 9), '');
    } finally {
      PathProviderPlatform.instance = originalProvider;
      await directory.delete(recursive: true);
    }
  });
}
