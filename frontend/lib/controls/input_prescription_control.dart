import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import '../services/prescription_local_ocr_service.dart';

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
  PrescriptionLocalOcrBoundary? _localOcrBoundary;
  final bool _ownsLocalOcrBoundary;
  final Duration requestTimeout;
  final Set<Completer<void>> _abortTriggers = <Completer<void>>{};
  int _lastRawMedicationCount = 0;
  int _lastParsedMedicationCount = 0;
  int _lastSkippedMedicationCount = 0;
  String _lastSelectedImagePath = '';
  List<RecognizedTextRegion> _lastRecognizedTextRegions = [];

  int get lastRawMedicationCount => _lastRawMedicationCount;
  int get lastParsedMedicationCount => _lastParsedMedicationCount;
  int get lastSkippedMedicationCount => _lastSkippedMedicationCount;
  String get lastSelectedImagePath => _lastSelectedImagePath;
  List<RecognizedTextRegion> get lastRecognizedTextRegions =>
      List.unmodifiable(_lastRecognizedTextRegions);

  InputPrescription({
    this.baseUrl = ApiConfig.baseUrl,
    ImagePicker? imagePicker,
    http.Client? client,
    PrescriptionLocalOcrBoundary? localOcrBoundary,
    this.requestTimeout = const Duration(seconds: 45),
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null,
       _localOcrBoundary = localOcrBoundary,
       _ownsLocalOcrBoundary = localOcrBoundary == null {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
  }

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

  // 함수이름: requestCapturedPrescriptionImage
  // 함수역할:
  // - 전용 카메라 화면에서 촬영한 처방전 파일로 OCR 분석을 요청한다.
  // 매개변수:
  // - image: 전용 카메라 화면에서 생성된 이미지 파일
  // - onImageSelected: 이미지 선택 완료 후 실행할 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록
  Future<List<MedicationSchedule>> requestCapturedPrescriptionImage(
    XFile image, {
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    _prepareSelectedImage(image.path);
    onImageSelected?.call();
    return _requestPrescriptionAnalysis(image, imageSource: ImageSource.camera);
  }

  // 함수이름: requestPrescriptionImage
  // 함수역할:
  // - 시스템 카메라로 처방전 이미지를 촬영하고 OCR 분석을 요청한다.
  // - 기존 호출부와 테스트 호환성을 위해 유지하며 앱 화면에서는 전용 카메라를 사용한다.
  // 매개변수:
  // - onImageSelected: 이미지 선택 직후 진행 상태로 전환하는 콜백
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

  // 함수이름: _requestPrescriptionAnalysis
  // 함수역할:
  // - 기기에서 OCR과 개인정보 제거를 수행한 뒤 비식별 텍스트만 백엔드에 전송한다.
  // - 백엔드가 반환한 조제일자를 각 약 일정에 함께 실어 보존한다.
  // 매개변수:
  // - image: 업로드할 처방전 이미지 파일
  // - imageSource: 파일 접근 오류 문구를 구분할 이미지 출처
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록
  Future<List<MedicationSchedule>> _requestPrescriptionAnalysis(
    XFile image, {
    ImageSource imageSource = ImageSource.camera,
  }) async {
    _lastRecognizedTextRegions = [];
    try {
      final localOcrResult = await _resolvedLocalOcrBoundary.recognizeAndMask(
        image.path,
      );
      _lastRecognizedTextRegions = localOcrResult.regions;
      final abortTrigger = Completer<void>();
      _abortTriggers.add(abortTrigger);
      final request = http.AbortableRequest(
        'POST',
        Uri.parse('$baseUrl/analyze-prescription-text'),
        abortTrigger: abortTrigger.future,
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'text': localOcrResult.maskedText});

      late final http.Response response;
      try {
        response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(
              requestTimeout,
              onTimeout: () {
                if (!abortTrigger.isCompleted) {
                  abortTrigger.complete();
                }
                throw StateError('처방전 분석 요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.');
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
      final serverRegions = RecognizedTextRegion.fromJsonList(
        decodedData['recognized_regions'] ?? decodedData['recognizedRegions'],
      );
      if (serverRegions.isNotEmpty) {
        _lastRecognizedTextRegions = serverRegions;
      }
      final prescriptionDate =
          decodedData['prescription_date']?.toString().trim() ?? '';
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        _recordParseCounts(decodedData, 0);
        return [];
      }

      final medicationSchedules = rawMedications
          .whereType<Map>()
          .map((item) {
            final itemJson = Map<String, dynamic>.from(item);
            itemJson.putIfAbsent('prescription_date', () => prescriptionDate);
            return MedicationSchedule.fromAnalysisJson(itemJson);
          })
          .toList(growable: false);
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

  // 함수이름: _requestPrescriptionImage
  // 함수역할:
  // - 이미지 소스별 선택 화면을 열고 선택된 파일의 OCR 분석을 요청한다.
  // 매개변수:
  // - imageSource: 카메라 또는 갤러리 이미지 소스
  // - onImageSelected: 이미지 선택 완료 후 실행할 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  Future<List<MedicationSchedule>?> _requestPrescriptionImage(
    ImageSource imageSource, {
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    _prepareSelectedImage('');
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
    _prepareSelectedImage(image.path);
    onImageSelected?.call();
    return _requestPrescriptionAnalysis(image, imageSource: imageSource);
  }

  void _prepareSelectedImage(String imagePath) {
    _lastSelectedImagePath = imagePath;
    _lastRecognizedTextRegions = [];
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
    final localOcrBoundary = _localOcrBoundary;
    if (_ownsLocalOcrBoundary &&
        localOcrBoundary is PrescriptionLocalOcrService) {
      unawaited(
        localOcrBoundary.dispose().catchError((Object error, StackTrace stack) {
          developer.log(
            '로컬 OCR 자원 해제에 실패했습니다.',
            name: 'InputPrescription',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
  }

  PrescriptionLocalOcrBoundary get _resolvedLocalOcrBoundary {
    return _localOcrBoundary ??= PrescriptionLocalOcrService();
  }
}
