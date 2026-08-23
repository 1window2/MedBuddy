import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image_library;
import 'package:path_provider/path_provider.dart';

// 파일명: manual_medication_image_store.dart
// 역할: 직접 등록한 알약 사진을 앱 내부 전용 저장소에서 관리한다.

// 클래스명: ManualMedicationImageStore
// 역할: 서버에 원본 사진을 보내지 않고 저장 복약 정보 식별자와 로컬 사진을 연결한다.
// 주요 책임:
// - 선택한 사진의 방향과 크기를 정규화해 앱 내부 폴더에 저장한다.
// - 저장 목록 조회 시 사진 경로를 복원한다.
// - 약 삭제 또는 보존기간 만료 뒤 남은 사진 파일을 함께 정리한다.
class ManualMedicationImageStore {
  static const int _maximumImageDimension = 1600;
  static const String _directoryName = 'manual_medication_images';

  const ManualMedicationImageStore();

  Future<String> saveImage({
    required String patientHash,
    required int medicationId,
    required String sourcePath,
  }) async {
    if (medicationId <= 0 || sourcePath.trim().isEmpty) {
      return '';
    }

    final sourceBytes = await File(sourcePath).readAsBytes();
    final decodedImage = image_library.decodeImage(sourceBytes);
    if (decodedImage == null) {
      throw const FormatException('선택한 사진 형식을 읽을 수 없습니다.');
    }

    var normalizedImage = image_library.bakeOrientation(decodedImage);
    if (normalizedImage.width > _maximumImageDimension ||
        normalizedImage.height > _maximumImageDimension) {
      normalizedImage = normalizedImage.width >= normalizedImage.height
          ? image_library.copyResize(
              normalizedImage,
              width: _maximumImageDimension,
            )
          : image_library.copyResize(
              normalizedImage,
              height: _maximumImageDimension,
            );
    }

    final directory = await _patientDirectory(patientHash);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$medicationId.jpg',
    );
    await destination.writeAsBytes(
      image_library.encodeJpg(normalizedImage, quality: 86),
      flush: true,
    );
    return destination.path;
  }

  Future<String> findImagePath({
    required String patientHash,
    required int medicationId,
  }) async {
    if (medicationId <= 0) {
      return '';
    }
    final directory = await _patientDirectory(patientHash, create: false);
    final imageFile = File(
      '${directory.path}${Platform.pathSeparator}$medicationId.jpg',
    );
    return await imageFile.exists() ? imageFile.path : '';
  }

  Future<void> deleteImage({
    required String patientHash,
    required int medicationId,
  }) async {
    final imagePath = await findImagePath(
      patientHash: patientHash,
      medicationId: medicationId,
    );
    if (imagePath.isNotEmpty) {
      await File(imagePath).delete();
    }
  }

  Future<void> removeOrphanImages({
    required String patientHash,
    required Set<int> activeMedicationIds,
  }) async {
    final directory = await _patientDirectory(patientHash, create: false);
    if (!await directory.exists()) {
      return;
    }
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.jpg')) {
        continue;
      }
      final fileName = entry.uri.pathSegments.last;
      final medicationId = int.tryParse(fileName.split('.').first);
      if (medicationId == null || !activeMedicationIds.contains(medicationId)) {
        await entry.delete();
      }
    }
  }

  Future<Directory> _patientDirectory(
    String patientHash, {
    bool create = true,
  }) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final encodedPatientHash = base64Url
        .encode(utf8.encode(patientHash.trim()))
        .replaceAll('=', '');
    final directory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$_directoryName'
      '${Platform.pathSeparator}$encodedPatientHash',
    );
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
