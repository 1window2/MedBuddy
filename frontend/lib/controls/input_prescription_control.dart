import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/medication_schedule_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

typedef PrescriptionImageSelectedCallback = void Function();

// 파일명: input_prescription_control.dart
// 역할: 카메라와 갤러리에서 처방전 이미지를 받아 백엔드 OCR API로 전송한다.

// 클래스명: InputPrescription
// 역할: 처방전 이미지 선택, 업로드, OCR 결과 변환을 담당한다.
// 주요 책임:
// - 카메라 또는 갤러리에서 이미지를 선택한다.
// - 이미지가 실제 선택된 뒤에만 진행 상태 콜백을 호출한다.
// - 백엔드 OCR 응답을 MedicationSchedule 목록으로 변환한다.
class InputPrescription {
  final String baseUrl;
  final ImagePicker _imagePicker;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Set<Completer<void>> _abortTriggers = <Completer<void>>{};
  int _lastRawMedicationCount = 0;
  int _lastParsedMedicationCount = 0;
  int _lastSkippedMedicationCount = 0;

  int get lastRawMedicationCount => _lastRawMedicationCount;
  int get lastParsedMedicationCount => _lastParsedMedicationCount;
  int get lastSkippedMedicationCount => _lastSkippedMedicationCount;

  InputPrescription({
    this.baseUrl = ApiConfig.baseUrl,
    ImagePicker? imagePicker,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 45),
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
  }

  // 함수명: requestPrescriptionImage
  // 함수역할:
  // - 카메라로 처방전 이미지를 촬영하고 OCR 분석을 요청한다.
  // 매개변수:
  // - onImageSelected: 이미지 선택 직후 진행 상태로 전환하는 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  // 함수명: requestPrescriptionImageFromGallery
  // 함수역할:
  // - 갤러리에서 처방전 이미지를 선택하고 OCR 분석을 요청한다.
  // 매개변수:
  // - onImageSelected: 이미지 선택 직후 진행 상태로 전환하는 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    return _requestPrescriptionImage(
      ImageSource.gallery,
      onImageSelected: onImageSelected,
    );
  }

  // 함수명: _requestPrescriptionImage
  // 함수역할:
  // - 이미지 소스별 공통 OCR 업로드 흐름을 처리한다.
  // - 백엔드가 반환한 조제일자를 각 약 일정에 함께 실어 보존한다.
  // 매개변수:
  // - imageSource: 카메라 또는 갤러리 이미지 소스
  // - onImageSelected: 이미지 선택 완료 후 실행할 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  Future<List<MedicationSchedule>?> requestPrescriptionImage({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    return _requestPrescriptionImage(
      ImageSource.camera,
      onImageSelected: onImageSelected,
    );
  }

  Future<List<MedicationSchedule>> _requestPrescriptionAnalysis(
    XFile image, {
    ImageSource imageSource = ImageSource.camera,
  }) async {
    try {
      final abortTrigger = Completer<void>();
      _abortTriggers.add(abortTrigger);
      final request = http.AbortableMultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload-prescription'),
        abortTrigger: abortTrigger.future,
      );
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      late final http.Response response;
      try {
        response =
            await _client.send(request).then(http.Response.fromStream).timeout(
          requestTimeout,
          onTimeout: () {
            if (!abortTrigger.isCompleted) {
              abortTrigger.complete();
            }
            throw StateError(
              '처방전 분석 요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.',
            );
          },
        );
      } finally {
        _abortTriggers.remove(abortTrigger);
      }
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          '분석 실패 (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final prescriptionDate =
          decodedData['prescription_date']?.toString().trim() ?? '';
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        _recordParseCounts(decodedData, 0);
        return [];
      }

      final medicationSchedules = rawMedications.whereType<Map>().map((item) {
        final itemJson = Map<String, dynamic>.from(item);
        itemJson.putIfAbsent('prescription_date', () => prescriptionDate);
        return MedicationSchedule.fromAnalysisJson(itemJson);
      }).toList(growable: false);
      _recordParseCounts(decodedData, medicationSchedules.length);
      return medicationSchedules;
    } on StateError {
      rethrow;
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'Prescription image file access failed.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError(_imageFileAccessErrorMessage(imageSource));
    } catch (error, stackTrace) {
      developer.log(
        'Prescription image upload failed.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('서버 연결에 실패했습니다.');
    }
  }

  Future<List<MedicationSchedule>?> _requestPrescriptionImage(
    ImageSource imageSource, {
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    final image = await _imagePicker.pickImage(
      source: imageSource,
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    if (image == null) {
      return null;
    }
    onImageSelected?.call();
    return _requestPrescriptionAnalysis(image, imageSource: imageSource);
  }

  String _imageFileAccessErrorMessage(ImageSource imageSource) {
    return imageSource == ImageSource.gallery
        ? '선택한 이미지 파일을 읽을 수 없습니다.'
        : '촬영한 이미지 파일을 읽을 수 없습니다.';
  }

  void _recordParseCounts(
    Map<String, dynamic> decodedData,
    int parsedMedicationCount,
  ) {
    _lastRawMedicationCount = _readCount(
      decodedData['raw_medication_count'] ?? decodedData['rawMedicationCount'],
      fallback: parsedMedicationCount,
    );
    _lastParsedMedicationCount = _readCount(
      decodedData['parsed_medication_count'] ??
          decodedData['parsedMedicationCount'],
      fallback: parsedMedicationCount,
    );
    _lastSkippedMedicationCount = _readCount(
      decodedData['skipped_medication_count'] ??
          decodedData['skippedMedicationCount'],
      fallback: _lastRawMedicationCount - _lastParsedMedicationCount,
    );
  }

  int _readCount(dynamic value, {required int fallback}) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    final parsedValue = int.tryParse(value?.toString().trim() ?? '');
    if (parsedValue == null) {
      return fallback < 0 ? 0 : fallback;
    }
    return parsedValue < 0 ? 0 : parsedValue;
  }

  void dispose() {
    for (final abortTrigger in _abortTriggers.toList(growable: false)) {
      if (!abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
    }
    _abortTriggers.clear();
    if (_ownsClient) {
      _client.close();
    }
  }
}
