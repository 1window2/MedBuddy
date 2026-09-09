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

// 함수이름: PrescriptionImageSelectedCallback
// 함수역할: 사용자가 실제 이미지를 선택한 직후에만 인식 진행 화면으로 전환하도록 알리는 콜백 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음.
typedef PrescriptionImageSelectedCallback = void Function();

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
  static const double _medicationRegionSimilarityThreshold = 0.75;
  static final RegExp _medicationFormPattern = RegExp(
    r'(건조시럽|캡슐|시럽|과립|연고|크림|패치|주사|흡입|점안|좌약|필름|'
    r'로션|스프레이|현탁액|정제|정|액|산|겔)',
    caseSensitive: false,
  );

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

  // Function Name: requestPrescriptionImageFromGallery
  // Description: Clears the prior preview, selects a bounded gallery image, signals only successful selection, and requests OCR analysis without claiming ownership of the gallery original.
  // Parameters:
  // - onImageSelected (PrescriptionImageSelectedCallback?): Progress receiver called immediately after actual image selection.
  // Returns:
  // - Future<List<MedicationSchedule>?>: Clears the prior preview, selects a bounded gallery image, signals only successful selection, and requests OCR analysis without claiming ownership of the gallery original.
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    await clearSelectedImage();
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
    _prepareSelectedImage(image.path, ownedByApp: false);
    onImageSelected?.call();
    return _requestPrescriptionAnalysis(
      image,
      imageSource: ImageSource.gallery,
    );
  }

  // Function Name: requestCapturedPrescriptionImage
  // Description: Clears the prior preview, records ownership of the app capture, signals selection, and analyzes the captured prescription.
  // Parameters:
  // - image (XFile): Local image file selected or captured by the user.
  // - onImageSelected (PrescriptionImageSelectedCallback?): Progress receiver called immediately after actual image selection.
  // Returns:
  // - Future<List<MedicationSchedule>>: Clears the prior preview, records ownership of the app capture, signals selection, and analyzes the captured prescription.
  Future<List<MedicationSchedule>> requestCapturedPrescriptionImage(
    XFile image, {
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    await clearSelectedImage();
    _prepareSelectedImage(image.path, ownedByApp: true);
    onImageSelected?.call();
    return _requestPrescriptionAnalysis(image, imageSource: ImageSource.camera);
  }

  // Function Name: _requestPrescriptionAnalysis
  // Description: Runs local OCR and redaction before uploading only masked text, preserves prescription date and batch metadata per schedule, records preview regions and parse counts, and tracks file use until completion.
  // Parameters:
  // - image (XFile): Local image file selected or captured by the user.
  // - imageSource (ImageSource): Camera or gallery source.
  // Returns:
  // - Future<List<MedicationSchedule>>: Runs local OCR and redaction before uploading only masked text, preserves prescription date and batch metadata per schedule, records preview regions and parse counts, and tracks file use until completion.
  Future<List<MedicationSchedule>> _requestPrescriptionAnalysis(
    XFile image, {
    ImageSource imageSource = ImageSource.camera,
  }) async {
    final imageOperation = Completer<void>();
    _activeImageOperations[image.path] = imageOperation;
    _lastRecognizedTextRegions = [];
    try {
      final localOcrResult = await _resolvedLocalOcrBoundary.recognizeAndMask(
        image.path,
      );
      final localRegions = localOcrResult.regions;
      _lastRecognizedTextRegions = localRegions;
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
              onTimeout: /* 함수이름: onTimeout 콜백
               * 함수역할: 처방전 분석 제한 시간을 넘기면 요청 중단 신호를 보내고 시간 초과 오류를 던진다.
               * 매개변수:
               * - 없음.
               * 반환값:
               * - 정상 반환하지 않으며 StateError를 던진다.
               */() {
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
      final prescriptionDate =
          decodedData['prescription_date']?.toString().trim() ?? '';
      final prescriptionBatchId =
          decodedData['prescription_batch_id']?.toString().trim() ?? '';
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        _lastRecognizedTextRegions = _resolvePreviewRegions(
          localRegions: localRegions,
          medicationSchedules: const [],
        );
        _recordParseCounts(decodedData, 0);
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
           */(item) {
            final itemJson = Map<String, dynamic>.from(item);
            itemJson.putIfAbsent('prescription_date', /* 함수이름: putIfAbsent 콜백
             * 함수역할: 응답 약에 처방 날짜가 없을 때 분석 요청의 처방 날짜를 보충한다.
             * 매개변수:
             * - 없음.
             * 반환값:
             * - 요청에서 사용한 처방 날짜.
             */() => prescriptionDate);
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
      _lastRecognizedTextRegions = _resolvePreviewRegions(
        localRegions: localRegions,
        medicationSchedules: medicationSchedules,
      );
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
        'Prescription text analysis request failed.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('서버 연결에 실패했습니다.');
    } finally {
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

  // Function Name: clearSelectedImage
  // Description: Releases preview references immediately, waits for OCR on an app-owned capture before deleting it, and never deletes a gallery original.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> clearSelectedImage() async {
    final imagePath = _lastSelectedImagePath;
    final ownedByApp = _lastSelectedImageOwnedByApp;
    final activeOperation = _activeImageOperations[imagePath];
    _prepareSelectedImage('', ownedByApp: false);
    if (!ownedByApp || imagePath.isEmpty) {
      return;
    }
    await activeOperation?.future;
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

  // Function Name: _resolvePreviewRegions
  // Description: Preserves sensitive masking regions, adds medication-matched OCR regions, removes duplicate category/box entries, and sorts the preview top-to-bottom then left-to-right.
  // Parameters:
  // - localRegions (List<RecognizedTextRegion>): Local OCR text and sensitive masking regions.
  // - medicationSchedules (List<MedicationSchedule>): Medication schedules used for lookup, comparison, or reminders.
  // Returns:
  // - List<RecognizedTextRegion>: Preserves sensitive masking regions, adds medication-matched OCR regions, removes duplicate category/box entries, and sorts the preview top-to-bottom then left-to-right.
  List<RecognizedTextRegion> _resolvePreviewRegions({
    required List<RecognizedTextRegion> localRegions,
    required List<MedicationSchedule> medicationSchedules,
  }) {
    final sensitiveRegions = localRegions.where(/* Function Name: where callback
     * Description: Selects OCR regions marked sensitive for image redaction.
     * Parameters:
     * - region (RecognizedTextRegion): OCR region being selected or reclassified.
     * Returns:
     * - Whether the region contains sensitive content.
     */(region) => region.isSensitive);
    final medicationRegions = _classifyLocalMedicationRegions(
      localRegions,
      medicationSchedules,
    );
    final uniqueRegions = <RecognizedTextRegion>[];
    final seenRegionKeys = <String>{};

    for (final region in [...sensitiveRegions, ...medicationRegions]) {
      final regionKey =
          '${region.category}:${region.box2d.map(/* 함수이름: map 콜백
           * 함수역할: 민감 영역 좌표를 반올림해 정수 경계값으로 맞춘다.
           * 매개변수:
           * - value (double): 반올림할 OCR 좌표
           * 반환값:
           * - 반올림된 좌표값.
           */(value) => value.round()).join(',')}';
      if (seenRegionKeys.add(regionKey)) {
        uniqueRegions.add(region);
      }
    }
    uniqueRegions.sort(/* 함수이름: sort 콜백
     * 함수역할: 민감 영역을 위쪽 좌표 우선, 같은 높이에서는 왼쪽 좌표 우선으로 정렬한다.
     * 매개변수:
     * - left (RecognizedTextRegion): 정렬 비교의 첫 번째 OCR 영역
     * - right (RecognizedTextRegion): 정렬 비교의 두 번째 OCR 영역
     * 반환값:
     * - 위·왼쪽 순서를 나타내는 음수·0·양수 비교값.
     */(left, right) {
      final topComparison = left.box2d[0].compareTo(right.box2d[0]);
      return topComparison != 0
          ? topComparison
          : left.box2d[1].compareTo(right.box2d[1]);
    });
    return List.unmodifiable(uniqueRegions);
  }

  // 함수이름: _classifyLocalMedicationRegions
  // 함수역할: 구조화된 약 이름과 일치하거나 충분히 유사한 로컬 OCR 문구만 약품 정보 영역으로 변환한다.
  // 매개변수:
  // - localRegions (List<RecognizedTextRegion>): 기기 내 OCR이 생성한 전체 영역
  // - medicationSchedules (List<MedicationSchedule>): 비교할 파싱 완료 약품 목록
  // 반환값:
  // - 약 이름과 대응된 로컬 OCR 영역 목록
  List<RecognizedTextRegion> _classifyLocalMedicationRegions(
    List<RecognizedTextRegion> localRegions,
    List<MedicationSchedule> medicationSchedules,
  ) {
    final medicationNames = <String>{
      for (final schedule in medicationSchedules)
        ...[
          _normalizeRegionText(schedule.medicationName),
          _normalizeRegionText(schedule.rawMedicationName),
        ].where(/* 함수이름: where 콜백
         * 함수역할: 짧은 문자열의 오탐을 줄이기 위해 세 글자 이상인 약 이름만 유지한다.
         * 매개변수:
         * - name (String): 표시·일치 여부를 검사할 약 이름
         * 반환값:
         * - 약 이름 길이가 3 이상이면 true.
         */(name) => name.length >= 3),
    };
    if (medicationNames.isEmpty) {
      return const [];
    }

    return localRegions
        .where(/* 함수이름: where 콜백
         * 함수역할: 명시적 약 영역과 약 이름에 대응하는 충분히 긴 일반 인식 영역만 선택한다.
         * 매개변수:
         * - region (RecognizedTextRegion): 선택 또는 재분류할 OCR 인식 영역
         * 반환값:
         * - 약 이름 영역으로 사용할 수 있으면 true.
         */(region) {
          if (region.isMedication) {
            return true;
          }
          if (region.category != 'recognized_text') {
            return false;
          }
          final regionText = _normalizeRegionText(region.text);
          if (regionText.length < 3) {
            return false;
          }
          return medicationNames.any(
            // 함수이름: any 콜백
            // 함수역할: 정규화된 인식 텍스트가 후보 약 이름과 일치하는지 검사한다.
            // 매개변수:
            // - name (String): 표시·일치 여부를 검사할 약 이름
            // 반환값:
            // - 해당 약 이름과 대응하면 true.
            (name) => _isMedicationRegionMatch(regionText, name),
          );
        })
        .map(
          // 함수이름: map 콜백
          // 함수역할: 기존 약 영역은 유지하고 일치한 일반 인식 영역은 약 이름 범주로 다시 표시한다.
          // 매개변수:
          // - region (RecognizedTextRegion): 선택 또는 재분류할 OCR 인식 영역
          // 반환값:
          // - 약 이름 범주가 부여된 인식 영역.
          (region) => region.isMedication
              ? region
              : RecognizedTextRegion(
                  category: 'medication_name',
                  text: region.text,
                  box2d: region.box2d,
                ),
        )
        .toList(growable: false);
  }

  // 함수이름: _isMedicationRegionMatch
  // 함수역할: 정확 포함 비교를 우선하고 OCR 한두 글자 오류는 편집거리 유사도로 보완한다. 유사도 비교에는 약품 제형 문구가 있는 영역만 허용해 일반 안내 문구의 오탐을 줄인다.
  // 매개변수:
  // - regionText (String): 정규화된 로컬 OCR 문구
  // - medicationName (String): 정규화된 파싱 완료 약 이름
  // 반환값:
  // - 약품 영역으로 볼 수 있으면 true
  bool _isMedicationRegionMatch(String regionText, String medicationName) {
    if (regionText.contains(medicationName) ||
        medicationName.contains(regionText)) {
      return true;
    }
    if (regionText.length < 4 ||
        medicationName.length < 4 ||
        !_medicationFormPattern.hasMatch(regionText)) {
      return false;
    }
    return _bestWindowSimilarity(regionText, medicationName) >=
        _medicationRegionSimilarityThreshold;
  }

  // 함수이름: _bestWindowSimilarity
  // 함수역할: 긴 문자열에 성분명이나 용량이 붙어도 약 이름과 가장 유사한 구간을 찾아 점수화한다.
  // 매개변수:
  // - left (String): 비교할 첫 번째 정규화 문자열
  // - right (String): 비교할 두 번째 정규화 문자열
  // 반환값:
  // - 0.0부터 1.0 사이의 최고 편집거리 유사도
  double _bestWindowSimilarity(String left, String right) {
    final shorter = left.length <= right.length ? left : right;
    final longer = left.length <= right.length ? right : left;
    var bestScore = _editSimilarity(shorter, longer);
    final minimumWindowLength = (shorter.length - 2).clamp(4, shorter.length);
    final maximumWindowLength = (shorter.length + 2).clamp(
      minimumWindowLength,
      longer.length,
    );

    for (
      var windowLength = minimumWindowLength;
      windowLength <= maximumWindowLength;
      windowLength++
    ) {
      for (var start = 0; start + windowLength <= longer.length; start++) {
        final window = longer.substring(start, start + windowLength);
        final score = _editSimilarity(shorter, window);
        if (score > bestScore) {
          bestScore = score;
        }
        if (bestScore >= 1) {
          return 1;
        }
      }
    }
    return bestScore;
  }

  // 함수이름: _editSimilarity
  // 함수역할: 두 문자열의 레벤슈타인 편집거리를 길이 대비 유사도로 변환한다.
  // 매개변수:
  // - left (String): 비교할 첫 번째 문자열
  // - right (String): 비교할 두 번째 문자열
  // 반환값:
  // - 완전히 같으면 1.0, 차이가 커질수록 0.0에 가까운 값
  double _editSimilarity(String left, String right) {
    final longestLength = left.length > right.length
        ? left.length
        : right.length;
    if (longestLength == 0) {
      return 1;
    }
    return 1 - (_levenshteinDistance(left, right) / longestLength);
  }

  // 함수이름: _levenshteinDistance
  // 함수역할: 삽입, 삭제, 치환으로 한 문자열을 다른 문자열로 바꾸는 최소 횟수를 계산한다.
  // 매개변수:
  // - left (String): 기준 문자열
  // - right (String): 비교 문자열
  // 반환값:
  // - 최소 편집 횟수
  int _levenshteinDistance(String left, String right) {
    if (left == right) {
      return 0;
    }
    if (left.isEmpty) {
      return right.length;
    }
    if (right.isEmpty) {
      return left.length;
    }

    var previousRow = List<int>.generate(right.length + 1, /* 함수이름: callback 콜백
     * 함수역할: 편집 거리 계산의 초기 행을 문자 위치별 삽입 비용으로 채운다.
     * 매개변수:
     * - index (int): 현재 목록 항목의 0부터 시작하는 위치
     * 반환값:
     * - 초기 위치와 같은 삽입 비용.
     */(index) => index);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex++) {
      final currentRow = List<int>.filled(right.length + 1, 0);
      currentRow[0] = leftIndex;
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex++) {
        final substitutionCost = left[leftIndex - 1] == right[rightIndex - 1]
            ? 0
            : 1;
        final insertion = currentRow[rightIndex - 1] + 1;
        final deletion = previousRow[rightIndex] + 1;
        final substitution = previousRow[rightIndex - 1] + substitutionCost;
        currentRow[rightIndex] = [
          insertion,
          deletion,
          substitution,
        ].reduce(/* 함수이름: reduce 콜백
         * 함수역할: 편집 거리 후보 비용에서 더 작은 값을 유지한다.
         * 매개변수:
         * - minimum (int): 지금까지 선택한 최소 편집 비용
         * - value (int): 비교할 편집 거리 비용
         * 반환값:
         * - 두 후보 중 작은 비용.
         */(minimum, value) => value < minimum ? value : minimum);
      }
      previousRow = currentRow;
    }
    return previousRow.last;
  }

  // 함수이름: _normalizeRegionText
  // 함수역할: OCR 문구와 파싱된 약 이름을 공백·기호 차이에 영향받지 않는 비교 문자열로 정리한다.
  // 매개변수:
  // - value (String): 비교할 OCR 문구 또는 약 이름
  // 반환값:
  // - 한글, 영문, 숫자만 남긴 소문자 문자열
  String _normalizeRegionText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '');
  }

  // Function Name: dispose
  // Description: Starts app-owned preview cleanup, aborts pending analysis requests, closes an owned HTTP client, and asynchronously releases an owned local OCR service.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    unawaited(clearSelectedImage());
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
        localOcrBoundary.dispose().catchError(/* 함수이름: catchError 콜백
         * 함수역할: 로컬 OCR 자원 해제 오류를 원인과 스택 정보와 함께 기록한다.
         * 매개변수:
         * - error (Object): 처리하거나 기록할 원래 실패 객체
         * - stack (StackTrace): 오류 발생 지점을 기록한 스택 추적
         * 반환값:
         * - 없음.
         */(Object error, StackTrace stack) {
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
