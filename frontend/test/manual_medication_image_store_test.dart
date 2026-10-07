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
}
