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

  // 함수이름: ManualMedicationImageStore
  // 함수역할: 직접 등록 사진의 방향·크기 정규화와 환자별 기기 저장 경로를 제공하는 저장 경계를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - ManualMedicationImageStore: 초기화된 인스턴스.
  const ManualMedicationImageStore();

  // 함수이름: saveImage
  // 함수역할: 유효한 저장 약 ID의 사진을 EXIF 방향과 최대 1600px로 정규화해 환자별 내부 폴더에 JPEG로 저장하며 원본은 서버에 전송하지 않는다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - medicationId (int): 대상 저장 복약정보의 식별자
  // - sourcePath (String): 기기에서 읽을 원본 이미지 경로
  // 반환값:
  // - Future<String>: 유효한 저장 약 ID의 사진을 EXIF 방향과 최대 1600px로 정규화해 환자별 내부 폴더에 JPEG로 저장하며 원본은 서버에 전송하지 않는다.
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

  // 함수이름: findImagePath
  // 함수역할: 환자 전용 폴더에서 해당 저장 약의 JPEG가 존재할 때만 경로를 제공하고 잘못된 ID나 없는 파일은 빈 문자열로 처리한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - medicationId (int): 대상 저장 복약정보의 식별자
  // 반환값:
  // - Future<String>: 환자 전용 폴더에서 해당 저장 약의 JPEG가 존재할 때만 경로를 제공하고 잘못된 ID나 없는 파일은 빈 문자열로 처리한다.
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

  // 함수이름: deleteImage
  // 함수역할: 환자와 저장 약 ID에 연결된 로컬 사진이 존재할 때 삭제한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - medicationId (int): 대상 저장 복약정보의 식별자
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: removeOrphanImages
  // 함수역할: 환자 폴더의 JPEG 중 현재 저장 약 ID 집합에 속하지 않거나 ID를 읽을 수 없는 고아 사진을 제거한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - activeMedicationIds (Set<int>): 사진을 유지할 현재 저장 약 ID 집합
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: _patientDirectory
  // 함수역할: 환자 해시를 base64url 경로 구간으로 변환해 앱 지원 폴더 아래 전용 디렉터리를 구하고 요청 시에만 생성한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - create (bool): 전용 사진 폴더가 없을 때 생성할지 여부
  // 반환값:
  // - Future<Directory>: 환자 해시를 base64url 경로 구간으로 변환해 앱 지원 폴더 아래 전용 디렉터리를 구하고 요청 시에만 생성한다.
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
