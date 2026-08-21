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

  int get lastRawMedicationCount => _lastRawMedicationCount;
  int get lastParsedMedicationCount => _lastParsedMedicationCount;
  int get lastSkippedMedicationCount => _lastSkippedMedicationCount;
  String get lastSelectedImagePath => _lastSelectedImagePath;
  bool get lastSelectedImageOwnedByApp => _lastSelectedImageOwnedByApp;
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
    await clearSelectedImage();
    _prepareSelectedImage(image.path, ownedByApp: true);
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
      final prescriptionDate =
          decodedData['prescription_date']?.toString().trim() ?? '';
      final prescriptionBatchId =
          decodedData['prescription_batch_id']?.toString().trim() ?? '';
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        _lastRecognizedTextRegions = _resolvePreviewRegions(
          localRegions: localRegions,
          serverRegions: serverRegions,
          medicationSchedules: const [],
        );
        _recordParseCounts(decodedData, 0);
        return [];
      }

      final medicationSchedules = rawMedications
          .whereType<Map>()
          .map((item) {
            final itemJson = Map<String, dynamic>.from(item);
            itemJson.putIfAbsent('prescription_date', () => prescriptionDate);
            itemJson.putIfAbsent(
              'prescription_batch_id',
              () => prescriptionBatchId,
            );
            return MedicationSchedule.fromAnalysisJson(itemJson);
          })
          .toList(growable: false);
      _lastRecognizedTextRegions = _resolvePreviewRegions(
        localRegions: localRegions,
        serverRegions: serverRegions,
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
        'Prescription image upload failed.',
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
    await clearSelectedImage();
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
    _prepareSelectedImage(
      image.path,
      ownedByApp: imageSource == ImageSource.camera,
    );
    onImageSelected?.call();
    return _requestPrescriptionAnalysis(image, imageSource: imageSource);
  }

  void _prepareSelectedImage(String imagePath, {required bool ownedByApp}) {
    _lastSelectedImagePath = imagePath;
    _lastSelectedImageOwnedByApp = ownedByApp;
    _lastRecognizedTextRegions = [];
  }

  // 함수이름: clearSelectedImage
  // 함수역할:
  // - 현재 미리보기 참조를 즉시 해제한다.
  // - 앱 카메라가 만든 임시 파일은 진행 중 OCR이 끝난 뒤 삭제하고,
  //   사용자가 선택한 갤러리 원본은 삭제하지 않는다.
  // 반환값:
  // - 필요한 파일 정리가 끝나면 완료되는 Future
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

  // 함수이름: _resolvePreviewRegions
  // 함수역할:
  // - 로컬 개인정보 마스킹 영역을 보존하면서 약품 관련 OCR 영역만 미리보기에 남긴다.
  // - 서버가 약품 좌표를 제공하면 이를 우선하고, 없으면 파싱된 약 이름으로 로컬 OCR 영역을 분류한다.
  // 매개변수:
  // - localRegions: 기기 내 OCR이 생성한 전체 텍스트 및 개인정보 영역
  // - serverRegions: 서버가 선택적으로 반환한 복약 정보 영역
  // - medicationSchedules: 서버가 구조화한 약품 일정 목록
  // 반환값:
  // - 약품 정보 영역과 개인정보 마스킹 영역만 포함한 정렬된 목록
  List<RecognizedTextRegion> _resolvePreviewRegions({
    required List<RecognizedTextRegion> localRegions,
    required List<RecognizedTextRegion> serverRegions,
    required List<MedicationSchedule> medicationSchedules,
  }) {
    final sensitiveRegions = [
      ...localRegions.where((region) => region.isSensitive),
      ...serverRegions.where((region) => region.isSensitive),
    ];
    final serverMedicationRegions = serverRegions
        .where((region) => region.isMedication)
        .toList(growable: false);
    final medicationRegions = serverMedicationRegions.isNotEmpty
        ? serverMedicationRegions
        : _classifyLocalMedicationRegions(localRegions, medicationSchedules);
    final uniqueRegions = <RecognizedTextRegion>[];
    final seenRegionKeys = <String>{};

    for (final region in [...sensitiveRegions, ...medicationRegions]) {
      final regionKey =
          '${region.category}:${region.box2d.map((value) => value.round()).join(',')}';
      if (seenRegionKeys.add(regionKey)) {
        uniqueRegions.add(region);
      }
    }
    uniqueRegions.sort((left, right) {
      final topComparison = left.box2d[0].compareTo(right.box2d[0]);
      return topComparison != 0
          ? topComparison
          : left.box2d[1].compareTo(right.box2d[1]);
    });
    return List.unmodifiable(uniqueRegions);
  }

  // 함수이름: _classifyLocalMedicationRegions
  // 함수역할:
  // - 구조화된 약 이름과 일치하거나 충분히 유사한 로컬 OCR 문구만 약품 정보 영역으로 변환한다.
  // 매개변수:
  // - localRegions: 기기 내 OCR이 생성한 전체 영역
  // - medicationSchedules: 비교할 파싱 완료 약품 목록
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
        ].where((name) => name.length >= 3),
    };
    if (medicationNames.isEmpty) {
      return const [];
    }

    return localRegions
        .where((region) {
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
            (name) => _isMedicationRegionMatch(regionText, name),
          );
        })
        .map(
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
  // 함수역할:
  // - 정확 포함 비교를 우선하고 OCR 한두 글자 오류는 편집거리 유사도로 보완한다.
  // - 유사도 비교에는 약품 제형 문구가 있는 영역만 허용해 일반 안내 문구의 오탐을 줄인다.
  // 매개변수:
  // - regionText: 정규화된 로컬 OCR 문구
  // - medicationName: 정규화된 파싱 완료 약 이름
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
  // 함수역할:
  // - 긴 문자열에 성분명이나 용량이 붙어도 약 이름과 가장 유사한 구간을 찾아 점수화한다.
  // 매개변수:
  // - left: 비교할 첫 번째 정규화 문자열
  // - right: 비교할 두 번째 정규화 문자열
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
  // 함수역할:
  // - 두 문자열의 레벤슈타인 편집거리를 길이 대비 유사도로 변환한다.
  // 매개변수:
  // - left: 비교할 첫 번째 문자열
  // - right: 비교할 두 번째 문자열
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
  // 함수역할:
  // - 삽입, 삭제, 치환으로 한 문자열을 다른 문자열로 바꾸는 최소 횟수를 계산한다.
  // 매개변수:
  // - left: 기준 문자열
  // - right: 비교 문자열
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

    var previousRow = List<int>.generate(right.length + 1, (index) => index);
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
        ].reduce((minimum, value) => value < minimum ? value : minimum);
      }
      previousRow = currentRow;
    }
    return previousRow.last;
  }

  // 함수이름: _normalizeRegionText
  // 함수역할:
  // - OCR 문구와 파싱된 약 이름을 공백·기호 차이에 영향받지 않는 비교 문자열로 정리한다.
  // 매개변수:
  // - value: 비교할 OCR 문구 또는 약 이름
  // 반환값:
  // - 한글, 영문, 숫자만 남긴 소문자 문자열
  String _normalizeRegionText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '');
  }

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
