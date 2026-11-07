import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/prescription_preview_regions.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import '../services/app_temp_file.dart';
import '../services/prescription_local_ocr_service.dart';

// 함수이름: PrescriptionImageSelectedCallback
// 함수역할: 사용자가 실제 이미지를 선택한 직후에만 인식 진행 화면으로 전환하도록 알리는 콜백 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음.
typedef PrescriptionImageSelectedCallback = void Function();
typedef PrescriptionRecognitionProgressCallback =
    void Function(PrescriptionRecognitionStage stage);

// 파일명: input_prescription_control.dart
// 역할: 처방전 이미지를 기기에서 비식별 처리하고 복약 정보 분석을 요청한다.

// Class Name: InputPrescription
// Role: Coordinates image selection, local OCR redaction, and structured prescription analysis.
// Responsibilities:
// - Accept camera or gallery files, notify only after selection, send redacted text rather than images, and decode schedules with prescription metadata.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - _imagePicker (ImagePicker): Camera and gallery image-selection boundary.
// - _client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
// - _localOcrBoundary (PrescriptionLocalOcrBoundary?): Boundary for on-device recognition and personal-data redaction.
// - requestTimeout (Duration): Maximum wait for an identification or analysis request.
class InputPrescription {
  final String baseUrl;
  final ImagePicker _imagePicker;
  final http.Client _client;
  final bool _ownsClient;
  PrescriptionLocalOcrBoundary? _localOcrBoundary;
  final bool _ownsLocalOcrBoundary;
  final Duration requestTimeout;
  final Set<Completer<void>> _abortTriggers = <Completer<void>>{};
  int _selectionGeneration = 0;
  bool _disposed = false;
  int _lastRawMedicationCount = 0;
  int _lastParsedMedicationCount = 0;
  int _lastSkippedMedicationCount = 0;
  String _lastSelectedImagePath = '';
  bool _lastSelectedImageOwnedByApp = false;
  List<RecognizedTextRegion> _lastRecognizedTextRegions = [];
  final Map<String, Completer<void>> _activeImageOperations =
      <String, Completer<void>>{};

  // Function Name: lastRawMedicationCount
  // Description: Exposes the server-reported number of raw medication entries from the latest prescription analysis.
  // Parameters:
  // - None.
  // Returns:
  // - int: The server-reported number of raw medication entries from the latest prescription analysis.
  int get lastRawMedicationCount => _lastRawMedicationCount;
  // Function Name: lastParsedMedicationCount
  // Description: Exposes the number of medication entries successfully parsed in the latest analysis.
  // Parameters:
  // - None.
  // Returns:
  // - int: The number of medication entries successfully parsed in the latest analysis.
  int get lastParsedMedicationCount => _lastParsedMedicationCount;
  // Function Name: lastSkippedMedicationCount
  // Description: Exposes the number of entries omitted by prescription parsing for partial-result guidance.
  // Parameters:
  // - None.
  // Returns:
  // - int: The number of entries omitted by prescription parsing for partial-result guidance.
  int get lastSkippedMedicationCount => _lastSkippedMedicationCount;
  // 함수이름: lastSelectedImagePath
  // 함수역할: 처방전 미리보기에 사용 중인 선택 파일 경로를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 처방전 미리보기에 사용 중인 선택 파일 경로를 제공한다.
  String get lastSelectedImagePath => _lastSelectedImagePath;
  // Function Name: lastSelectedImageOwnedByApp
  // Description: Reports whether the preview file was created by app capture and may be deleted during cleanup.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether the preview file was created by app capture and may be deleted during cleanup.
  bool get lastSelectedImageOwnedByApp => _lastSelectedImageOwnedByApp;
  // 함수이름: lastRecognizedTextRegions
  // 함수역할: 미리보기의 약품 강조 및 개인정보 마스킹 영역을 외부에서 변경할 수 없는 목록으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<RecognizedTextRegion>: 미리보기의 약품 강조 및 개인정보 마스킹 영역을 외부에서 변경할 수 없는 목록으로 제공한다.
  List<RecognizedTextRegion> get lastRecognizedTextRegions =>
      List.unmodifiable(_lastRecognizedTextRegions);

  // 함수이름: InputPrescription
  // 함수역할: 이미지 선택·인증 HTTP·지연 생성 로컬 OCR 의존성을 연결하고 자원 소유권과 양수 분석 제한 시간을 검증한다.
  // 매개변수:
  // - baseUrl (String): 복약 API 기본 주소
  // - imagePicker (ImagePicker?): 카메라·갤러리 이미지 선택 경계
  // - client (http.Client?): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - localOcrBoundary (PrescriptionLocalOcrBoundary?): 기기 내 인식·개인정보 제거 경계
  // - requestTimeout (Duration): 식별·분석 요청의 최대 대기시간
  // 반환값:
  // - InputPrescription: 초기화된 인스턴스.
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

  // 함수이름: requestPrescriptionImageFromGallery
  // 함수역할: 갤러리 사진을 선택한 뒤 이전 미리보기를 정리하고 OCR 분석을 시작한다. 선택 취소는 이전 사진을 유지한다.
  // 매개변수: onImageSelected: 실제 선택 알림; onProgress: 인식 단계 알림.
  // 반환값: 인식 일정 목록 또는 취소·오래된 선택의 경우 null; 갤러리 원본 소유권을 가져오지 않는다.
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
    PrescriptionRecognitionProgressCallback? onProgress,
  }) async {
    if (_disposed) return null;
    final generation = ++_selectionGeneration;
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    if (image == null) {
      return null;
    }
    if (!_isCurrentSelection(generation)) {
      await _discardUnusedImage(image.path, ownedByApp: false);
      return null;
    }
    // The picker reuses its cache file name when the same photo is chosen again; that file now holds the new pick and must not be deleted with the previous selection.
    await _releaseSelectedImage(
      deleteFile: image.path != _lastSelectedImagePath,
    );
    if (!_isCurrentSelection(generation)) {
      await _discardUnusedImage(image.path, ownedByApp: false);
      return null;
    }
    _prepareSelectedImage(image.path, ownedByApp: false);
    onImageSelected?.call();
    if (!_isCurrentSelection(generation)) return null;
    return _requestPrescriptionAnalysis(
      image,
      imageSource: ImageSource.gallery,
      onProgress: onProgress,
    );
  }

  // 함수이름: requestCapturedPrescriptionImage
  // 함수역할: 앱 촬영 이미지의 소유권을 기록하고 선택 세대가 유효한 경우에만 분석을 시작한다.
  // 매개변수: image: 촬영한 XFile; onImageSelected: 선택 완료 알림; onProgress: 인식 단계 알림.
  // 반환값: 인식 일정 목록 Future; 취소된 흐름은 StateError이며 사용하지 않는 앱 이미지를 정리한다.
  Future<List<MedicationSchedule>> requestCapturedPrescriptionImage(
    XFile image, {
    PrescriptionImageSelectedCallback? onImageSelected,
    PrescriptionRecognitionProgressCallback? onProgress,
  }) async {
    final generation = ++_selectionGeneration;
    if (!_disposed) {
      await _releaseSelectedImage(
        deleteFile: image.path != _lastSelectedImagePath,
      );
    }
    if (!_isCurrentSelection(generation)) {
      await _discardUnusedImage(image.path, ownedByApp: true);
      throw StateError('Prescription analysis was cancelled.');
    }
    _prepareSelectedImage(image.path, ownedByApp: true);
    onImageSelected?.call();
    if (!_isCurrentSelection(generation)) {
      throw StateError('Prescription analysis was cancelled.');
    }
    return _requestPrescriptionAnalysis(
      image,
      imageSource: ImageSource.camera,
      onProgress: onProgress,
    );
  }

  // Function Name: _requestPrescriptionAnalysis
  // Description: Performs local OCR and masking, sends only masked text to the server and merges prescription metadata into parsed schedules.
  // Parameters: image: Local image; imageSource: Capture/gallery origin for file-error guidance; onProgress: Recognition-stage callback.
  // Returns: Recognized schedules, or an empty list when no medication list is present; cancellation and file access become StateError, other failures retain their type.
  Future<List<MedicationSchedule>> _requestPrescriptionAnalysis(
    XFile image, {
    ImageSource imageSource = ImageSource.camera,
    PrescriptionRecognitionProgressCallback? onProgress,
  }) async {
    final imageOperation = Completer<void>();
    final abortTrigger = Completer<void>();
    _abortTriggers.add(abortTrigger);
    _activeImageOperations[image.path] = imageOperation;
    _lastRecognizedTextRegions = [];
    var failureStage = 'local OCR';
    try {
      onProgress?.call(PrescriptionRecognitionStage.recognizingText);
      final localOcrResult = await _resolvedLocalOcrBoundary.recognizeAndMask(
        image.path,
      );
      if (abortTrigger.isCompleted) {
        throw StateError('Prescription analysis was cancelled.');
      }
      final localRegions = localOcrResult.regions;
      _lastRecognizedTextRegions = localRegions;
      onProgress?.call(PrescriptionRecognitionStage.structuringMedication);
      failureStage = 'server request';
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
              onTimeout: /* 함수이름: onTimeout 콜백
               * 함수역할: 처방전 분석 제한 시간을 넘기면 요청 중단 신호를 보내고 시간 초과 오류를 던진다.
               * 매개변수:
               * - 없음.
               * 반환값:
               * - 정상 반환하지 않으며 StateError를 던진다.
               */ () {
                if (!abortTrigger.isCompleted) {
                  abortTrigger.complete();
                }
                throw StateError('처방전 분석 요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.');
              },
            );
      } finally {
        _abortTriggers.remove(abortTrigger);
      }
      // 중단을 지원하지 않는 응답 경계도 취소된 결과로 상태를 되살리지 못하게 한다.
      if (abortTrigger.isCompleted) {
        throw StateError('Prescription analysis was cancelled.');
      }
      failureStage = 'response parsing';
      final responseBody = ApiResponseParser.requireOkBody('분석 실패', response);

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final prescriptionDate =
          decodedData['prescription_date']?.toString().trim() ?? '';
      final prescriptionBatchId =
          decodedData['prescription_batch_id']?.toString().trim() ?? '';
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        _lastRecognizedTextRegions = resolvePrescriptionPreviewRegions(
          localRegions: localRegions,
          medicationSchedules: const [],
        );
        _recordParseCounts(decodedData, 0);
        onProgress?.call(PrescriptionRecognitionStage.completed);
        return [];
      }

      final medicationSchedules = rawMedications
          .whereType<Map>()
          .map(/* Function Name: map callback
           * Description: Supplies missing prescription date and batch metadata before parsing each analysis result into a medication schedule.
           * Parameters:
           * - item (Map): Current response or collection entry being transformed or checked.
           * Returns:
           * - The parsed schedule with inherited prescription metadata.
           */ (item) {
            final itemJson = Map<String, dynamic>.from(item);
            itemJson.putIfAbsent(
              'prescription_date',
              /* 함수이름: putIfAbsent 콜백
             * 함수역할: 응답 약에 처방 날짜가 없을 때 분석 요청의 처방 날짜를 보충한다.
             * 매개변수:
             * - 없음.
             * 반환값:
             * - 요청에서 사용한 처방 날짜.
             */
              () => prescriptionDate,
            );
            itemJson.putIfAbsent(
              'prescription_batch_id',
              // Function Name: putIfAbsent callback
              // Description: Supplies the analysis batch ID only when the medication response omits it.
              // Parameters:
              // - None.
              // Returns:
              // - The enclosing prescription batch ID.
              () => prescriptionBatchId,
            );
            return MedicationSchedule.fromAnalysisJson(itemJson);
          })
          .toList(growable: false);
      _lastRecognizedTextRegions = resolvePrescriptionPreviewRegions(
        localRegions: localRegions,
        medicationSchedules: medicationSchedules,
      );
      _recordParseCounts(decodedData, medicationSchedules.length);
      onProgress?.call(PrescriptionRecognitionStage.completed);
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
        'Prescription recognition failed during $failureStage.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _abortTriggers.remove(abortTrigger);
      if (identical(_activeImageOperations[image.path], imageOperation)) {
        _activeImageOperations.remove(image.path);
      }
      if (!imageOperation.isCompleted) {
        imageOperation.complete();
      }
    }
  }

  // Function Name: _prepareSelectedImage
  // Description: Replaces the preview path and ownership flag and clears regions left by the previous image.
  // Parameters:
  // - imagePath (String): Source image path to read on the device.
  // - ownedByApp (bool): Whether the app owns the capture and may delete it during cleanup.
  // Returns:
  // - No return value.
  void _prepareSelectedImage(String imagePath, {required bool ownedByApp}) {
    _lastSelectedImagePath = imagePath;
    _lastSelectedImageOwnedByApp = ownedByApp;
    _lastRecognizedTextRegions = [];
  }

  // 함수이름: clearSelectedImage
  // 함수역할: 선택 세대를 무효화하고 미리보기를 즉시 해제한 뒤 이미지 사용 종료를 기다려 소유권 규칙에 따라 파일을 정리한다.
  // 매개변수: 없음.
  // 반환값: 정리 완료 Future; 앱 촬영본 또는 앱 임시 폴더의 선택기 사본만 삭제 대상이다.
  Future<void> clearSelectedImage() {
    _selectionGeneration++;
    return _releaseSelectedImage(deleteFile: true);
  }

  // 함수이름: _isCurrentSelection
  // 함수역할: 비동기 선택이나 정리를 기다린 작업이 아직 현재 흐름인지 확인한다.
  // 매개변수: generation: 작업 시작 때 저장한 선택 세대 번호.
  // 반환값: 객체가 종료되지 않았고 현재 세대와 같으면 true.
  bool _isCurrentSelection(int generation) =>
      !_disposed && generation == _selectionGeneration;

  // 함수이름: _discardUnusedImage
  // 함수역할: 현재 선택이나 진행 중 OCR이 사용하지 않는 이미지만 정리한다.
  // 매개변수: imagePath: 정리 후보 경로; ownedByApp: 앱 촬영본 여부.
  // 반환값: 정리 완료 Future; 사용 중 경로는 그대로 둔다.
  Future<void> _discardUnusedImage(
    String imagePath, {
    required bool ownedByApp,
  }) async {
    if (imagePath == _lastSelectedImagePath ||
        _activeImageOperations.containsKey(imagePath)) {
      return;
    }
    await _deleteImageFile(imagePath, ownedByApp: ownedByApp);
  }

  // 함수이름: _releaseSelectedImage
  // 함수역할: 선택 이미지 참조를 먼저 비우고 진행 중 읽기를 기다린 뒤 허용된 경우 파일을 삭제한다.
  // 매개변수: deleteFile: 파일 삭제 허용 여부; 같은 경로가 새 선택에 재사용되면 삭제하지 않는다.
  // 반환값: 해제 완료 Future; 소유권에 따른 파일 정리 경계를 사용한다.
  Future<void> _releaseSelectedImage({required bool deleteFile}) async {
    final imagePath = _lastSelectedImagePath;
    final ownedByApp = _lastSelectedImageOwnedByApp;
    final activeOperation = _activeImageOperations[imagePath];
    _prepareSelectedImage('', ownedByApp: false);
    if (imagePath.isEmpty) {
      return;
    }
    await activeOperation?.future;
    if (!deleteFile || imagePath == _lastSelectedImagePath) {
      return;
    }
    await _deleteImageFile(imagePath, ownedByApp: ownedByApp);
  }

  // 함수이름: _deleteImageFile
  // 함수역할: 앱 촬영본을 삭제하거나 선택기 사본을 앱 임시 폴더 제한 삭제 함수에 맡긴다.
  // 매개변수: imagePath: 정리할 파일 경로; ownedByApp: 앱이 직접 소유하는 촬영본인지 여부.
  // 반환값: 정리 완료 Future; 촬영본 파일 시스템 오류는 로그에 남기고 삼킨다.
  Future<void> _deleteImageFile(
    String imagePath, {
    required bool ownedByApp,
  }) async {
    if (!ownedByApp) {
      // The Android picker hands back a resized copy in the app cache, not the user's photo; the helper refuses any path outside the app temporary directory.
      await deleteAppTempFile(imagePath);
      return;
    }
    final imageFile = File(imagePath);
    try {
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'App-owned prescription capture cleanup failed.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // Function Name: _imageFileAccessErrorMessage
  // Description: Selects the camera-capture or gallery-file access error message from the image source.
  // Parameters:
  // - imageSource (ImageSource): Camera or gallery source.
  // Returns:
  // - String: Selects the camera-capture or gallery-file access error message from the image source.
  String _imageFileAccessErrorMessage(ImageSource imageSource) {
    return imageSource == ImageSource.gallery
        ? '선택한 이미지 파일을 읽을 수 없습니다.'
        : '촬영한 이미지 파일을 읽을 수 없습니다.';
  }

  // Function Name: _recordParseCounts
  // Description: Records raw, parsed, and skipped medication counts from either server key style, falling back to the decoded list length and clamping negative counts.
  // Parameters:
  // - decodedData (Map<String, dynamic>): Decoded server response object.
  // - parsedMedicationCount (int): Number of successfully decoded medication schedules.
  // Returns:
  // - No return value.
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

  // Function Name: _readCount
  // Description: Parses a nonnegative count, using a nonnegative fallback when the value is not an integer or numeric string.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // - fallback (int): Fallback for absent or unparseable input.
  // Returns:
  // - int: Parses a nonnegative count, using a nonnegative fallback when the value is not an integer or numeric string.
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

  // 함수이름: cancelPendingRequests
  // 함수역할: 진행 중 선택 세대와 분석 요청을 취소하되 재사용할 서비스는 해제하지 않는다.
  // 매개변수: 없음.
  // 반환값: 없음; 각 미완료 요청에 중단 신호를 보내고 목록을 비운다.
  void cancelPendingRequests() {
    _selectionGeneration++;
    for (final abortTrigger in _abortTriggers.toList(growable: false)) {
      if (!abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
    }
    _abortTriggers.clear();
  }

  // 함수이름: dispose
  // 함수역할: 추가 선택을 막고 이미지 정리·요청 취소와 소유한 HTTP/OCR 자원 해제를 시작한다.
  // 매개변수: 없음.
  // 반환값: 없음; 파일과 OCR 해제는 비동기이며 반복 종료는 무시한다.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(clearSelectedImage());
    cancelPendingRequests();
    if (_ownsClient) {
      _client.close();
    }
    final localOcrBoundary = _localOcrBoundary;
    if (_ownsLocalOcrBoundary &&
        localOcrBoundary is PrescriptionLocalOcrService) {
      unawaited(
        localOcrBoundary.dispose().catchError(/* 함수이름: catchError 콜백
         * 함수역할: 로컬 OCR 자원 해제 오류를 원인과 스택 정보와 함께 기록한다.
         * 매개변수:
         * - error (Object): 처리하거나 기록할 원래 실패 객체
         * - stack (StackTrace): 오류 발생 지점을 기록한 스택 추적
         * 반환값:
         * - 없음.
         */ (Object error, StackTrace stack) {
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

  // 함수이름: _resolvedLocalOcrBoundary
  // 함수역할: 주입된 OCR 경계를 재사용하고 없을 때에만 로컬 OCR 서비스를 지연 생성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PrescriptionLocalOcrBoundary: 주입된 OCR 경계를 재사용하고 없을 때에만 로컬 OCR 서비스를 지연 생성한다.
  PrescriptionLocalOcrBoundary get _resolvedLocalOcrBoundary {
    return _localOcrBoundary ??= PrescriptionLocalOcrService();
  }
}
