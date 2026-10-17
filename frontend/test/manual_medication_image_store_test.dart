// 직접 등록 사진의 백그라운드 압축과 계정별 저장을 검증한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';

class _ImagePaths extends PathProviderPlatform {
  final String root;
  _ImagePaths(this.root);
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  // 처방 변경으로 새 ID가 생겨도 기기 사진이 새 항목에 이어지고 이전 기록 행의 사진은 남는다.
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
