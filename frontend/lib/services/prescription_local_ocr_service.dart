import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../entities/recognized_text_region_entity.dart';
import 'prescription_ocr_reading_order.dart';

// 파일명: prescription_local_ocr_service.dart
// 역할: 처방전 원본이 기기를 벗어나기 전에 한글 OCR과 개인정보 제거를 수행한다.

// 클래스명: LocalPrescriptionOcrResult
// 역할: 서버 전송용 비식별 텍스트와 로컬 미리보기 영역을 묶는다.
// 주요 책임:
// - 원본 개인정보를 보내지 않고 약품 강조와 민감정보 마스킹 좌표를 함께 전달한다.
// 속성:
// - maskedText (String): 개인정보가 제거된 처방전 OCR 텍스트
// - regions (List<RecognizedTextRegion>): 로컬 OCR의 문구 및 개인정보 마스킹 영역
class LocalPrescriptionOcrResult {
  final String maskedText;
  final List<RecognizedTextRegion> regions;

  // 함수이름: LocalPrescriptionOcrResult
  // 함수역할: 개인정보를 제거한 전송 텍스트와 로컬 화면용 OCR 영역을 하나의 인식 결과로 묶는다.
  // 매개변수:
  // - maskedText (String): 개인정보가 제거된 처방전 OCR 텍스트
  // - regions (List<RecognizedTextRegion>): 로컬 OCR의 문구 및 개인정보 마스킹 영역
  // 반환값:
  // - LocalPrescriptionOcrResult: 초기화된 인스턴스.
  const LocalPrescriptionOcrResult({
    required this.maskedText,
    required this.regions,
  });
}

// 클래스명: PrescriptionLocalOcrBoundary
// 역할: 처방전 이미지의 로컬 문자 인식과 개인정보 가림 결과를 제공하는 계약이다.
// 주요 책임: 이미지 경로를 받아 안전한 텍스트·영역 결과 또는 실패를 반환하도록 한다.
// 속성: 저장 상태 없음; recognizeAndMask 비동기 경계만 노출한다.
abstract interface class PrescriptionLocalOcrBoundary {
  // 함수이름: recognizeAndMask
  // 함수역할: 로컬 처방전 파일에서 개인정보를 제거한 텍스트와 미리보기 영역을 얻는 비동기 인식 계약을 제공한다.
  // 매개변수:
  // - imagePath (String): 기기에서 읽을 원본 이미지 경로
  // 반환값:
  // - Future<LocalPrescriptionOcrResult>: 로컬 처방전 파일에서 개인정보를 제거한 텍스트와 미리보기 영역을 얻는 비동기 인식 계약을 제공한다.
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath);
}

// Class Name: PrescriptionLocalOcrService
// Role: Extract locally recognized prescription text with privacy filtering and preview regions.
// Responsibilities: Mask sensitive lines/identifiers and order remaining text by document layout.
// Attributes: _textRecognizer (TextRecognizer): OCR engine; _privacyFilter (PrescriptionPrivacyFilter): masking rules; _maximumPreviewRegions (int): 80 nonsensitive regions, without capping sensitive regions.
class PrescriptionLocalOcrService implements PrescriptionLocalOcrBoundary {
  static const int _maximumPreviewRegions = 80;

  final TextRecognizer _textRecognizer;
  final PrescriptionPrivacyFilter _privacyFilter;

  // 함수이름: PrescriptionLocalOcrService
  // 함수역할: 한글 텍스트 인식기와 개인정보 필터를 주입하거나 기본 로컬 구현으로 구성한다.
  // 매개변수:
  // - textRecognizer (TextRecognizer?): 기기 내 한글 OCR 인식기
  // - privacyFilter (PrescriptionPrivacyFilter?): OCR 개인정보 라벨·식별자 제거 규칙
  // 반환값:
  // - PrescriptionLocalOcrService: 초기화된 인스턴스.
  PrescriptionLocalOcrService({
    TextRecognizer? textRecognizer,
    PrescriptionPrivacyFilter? privacyFilter,
  }) : _textRecognizer =
           textRecognizer ??
           TextRecognizer(script: TextRecognitionScript.korean),
       _privacyFilter = privacyFilter ?? const PrescriptionPrivacyFilter();

  // Function Name: recognizeAndMask
  // Description: Recognize image text, mask sensitive content and sort safe lines into reading order; fail when no usable nonsensitive text remains.
  // Parameters: imagePath (String): local prescription image path.
  // Returns: Future<LocalPrescriptionOcrResult>: masked text and immutable regions; OCR/file failures and empty-safe-text errors propagate.
  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    final imageSize = await _readImageSize(imagePath);
    final safeLines = <int, String>{};
    final regions = <RecognizedTextRegion>[];
    var plainRegionCount = 0;
    final lines = [
      for (final block in recognizedText.blocks)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty) line,
    ];
    final sensitiveFlags = _privacyFilter.sensitiveLineFlags([
      for (final line in lines) line.text.trim(),
    ]);

    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      final text = line.text.trim();
      final sensitive = sensitiveFlags[index];
      final region = _toRegion(
        text: sensitive ? '' : _privacyFilter.maskInlineIdentifiers(text),
        bounds: line.boundingBox,
        imageSize: imageSize,
        category: sensitive ? 'sensitive_info' : _categoryForSafeText(text),
      );
      // 개인정보 영역은 항상 남겨 미리보기에서 가려지게 하고, 상한은 일반 영역에만 적용한다.
      if (region != null) {
        if (sensitive) {
          regions.add(region);
        } else if (plainRegionCount < _maximumPreviewRegions) {
          regions.add(region);
          plainRegionCount += 1;
        }
      }
      if (!sensitive) {
        final maskedLine = _privacyFilter.maskInlineIdentifiers(text).trim();
        if (maskedLine.isNotEmpty) {
          safeLines[index] = maskedLine;
        }
      }
    }

    // 인식기는 열 단위 블록으로 줄을 돌려주므로 약 이름과 그 행의 용법이 멀리 떨어진다. 화면의 행 순서로
    // 다시 놓아 같은 행의 줄이 이어지게 한다. 개인정보 판단은 위에서 원래 순서로 이미 끝났다.
    final maskedText = [
      for (final index in PrescriptionOcrReadingOrder.order([
        for (final line in lines) line.boundingBox,
      ], safeLines.keys.toList()))
        safeLines[index]!,
    ].join('\n').trim();
    if (maskedText.isEmpty) {
      throw StateError('기기에서 처방전 글자를 인식하지 못했거나 개인정보 외의 내용을 찾지 못했습니다.');
    }
    return LocalPrescriptionOcrResult(
      maskedText: maskedText,
      regions: List.unmodifiable(regions),
    );
  }

  // 함수이름: _readImageSize
  // 함수역할: OCR 픽셀 좌표를 화면 공통 좌표로 변환할 수 있도록 이미지 크기를 읽는다.
  // 매개변수:
  // - imagePath (String): 기기에서 읽을 원본 이미지 경로
  // 반환값:
  // - Future<ui.Size>: OCR 픽셀 좌표를 화면 공통 좌표로 변환할 수 있도록 이미지 크기를 읽는다.
  Future<ui.Size> _readImageSize(String imagePath) async {
    final bytes = await ui.ImmutableBuffer.fromFilePath(imagePath);
    final descriptor = await ui.ImageDescriptor.encoded(bytes);
    try {
      return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } finally {
      descriptor.dispose();
      bytes.dispose();
    }
  }

  // 함수이름: _categoryForSafeText
  // 함수역할: 안전한 문구에 조제·처방 날짜 라벨이 있으면 날짜 영역으로, 없으면 일반 인식 영역으로 분류한다.
  // 매개변수:
  // - text (String): 인식·정규화·마스킹·읽기에 사용할 문구
  // 반환값:
  // - String: 안전한 문구에 조제·처방 날짜 라벨이 있으면 날짜 영역으로, 없으면 일반 인식 영역으로 분류한다.
  String _categoryForSafeText(String text) {
    return PrescriptionPrivacyFilter.prescriptionDateLabelPattern.hasMatch(text)
        ? 'prescription_date'
        : 'recognized_text';
  }

  // 함수이름: _toRegion
  // 함수역할: 양의 이미지·영역 크기를 확인하고 픽셀 경계를 0~1000 좌표로 제한해 유효한 미리보기 영역만 만든다.
  // 매개변수:
  // - text (String): 인식·정규화·마스킹·읽기에 사용할 문구
  // - bounds (ui.Rect): OCR이 인식한 원본 픽셀 경계
  // - imageSize (ui.Size): OCR 픽셀 좌표 정규화에 사용할 원본 크기
  // - category (String): 약품·날짜·개인정보 등 OCR 영역 분류
  // 반환값:
  // - RecognizedTextRegion?: 양의 이미지·영역 크기를 확인하고 픽셀 경계를 0~1000 좌표로 제한해 유효한 미리보기 영역만 만든다.
  RecognizedTextRegion? _toRegion({
    required String text,
    required ui.Rect bounds,
    required ui.Size imageSize,
    required String category,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return null;
    }
    final box = <double>[
      (bounds.top / imageSize.height * 1000).clamp(0, 1000).toDouble(),
      (bounds.left / imageSize.width * 1000).clamp(0, 1000).toDouble(),
      (bounds.bottom / imageSize.height * 1000).clamp(0, 1000).toDouble(),
      (bounds.right / imageSize.width * 1000).clamp(0, 1000).toDouble(),
    ];
    final region = RecognizedTextRegion(
      category: category,
      text: text,
      box2d: box,
    );
    return region.isValid ? region : null;
  }

  // 함수이름: dispose
  // 함수역할: ML Kit 네이티브 텍스트 인식 자원을 해제한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}

// Class Name: PrescriptionPrivacyFilter
// Role: Identify prescription text that may contain personal information.
// Responsibilities: Detect sensitive labels and adjacent value rows, retain medication rows, and mask inline identifiers.
// Attributes: Static RegExp fields: sensitive/neutral labels, medication cues and identifier/value patterns; no instance state.
class PrescriptionPrivacyFilter {
  static final RegExp _sensitiveLabelPattern = RegExp(
    // "성 명"은 앞 글자가 한글이 아닐 때만 라벨로 본다. "서방성 명…" 같은 약 문구를 지우지 않기 위해서다.
    r'(환자\s*(명|성명|이름|번호|정보)|수진자(\s*(명|성명))?|(?<![가-힣])성\s*명|'
    r'주민\s*(등록)?\s*번호|'
    r'생년\s*월일|주소|전화\s*번호|연락처|휴대폰|보험\s*번호|'
    r'차트\s*번호|의무\s*기록\s*번호)',
    caseSensitive: false,
  );
  // 나이·성별 라벨은 그 자체로는 개인정보가 아니지만, 개인정보 라벨과 함께 나열되면 값 줄 수를 세는 데 포함한다.
  static final RegExp _neutralLabelPattern = RegExp(r'(연령|나이|성별)');
  // 한 줄에 라벨이 여럿일 때 라벨 사이나 끝에 올 수 있는 구분 기호다.
  static final RegExp _labelSeparatorPattern = RegExp(r'[\s/·ㆍ・:：|,()\[\]]+');
  // 용량·횟수 단위가 붙은 숫자나 제형 이름이 있으면 약 행으로 본다. 이름·주소·번호 값에는 나오지 않는 표기만 쓴다.
  static final RegExp _medicationRowPattern = RegExp(
    r'\d\s*(?:mg|㎎|mcg|㎍|µg|μg|ml|㎖|g|iu)(?![a-z])'
    r'|\d\s*(?:밀리그램|정|캡슐|캅셀|포|회|일분)(?:씩|(?![가-힣]))'
    r'|(?:캡슐|캅셀|시럽|현탁액|점안액|연고|서방정|장용정)(?![가-힣])',
    caseSensitive: false,
  );
  // 한 줄에 붙어 인식된 값 중 생년월일을 세기 위한 날짜 표기다.
  static final RegExp _birthDateValuePattern = RegExp(
    r'(?<!\d)(?:19|20)\d{2}\s*[.\-/년]\s*\d{1,2}\s*[.\-/월]\s*\d{1,2}\s*일?',
  );
  static final RegExp _genderValuePattern = RegExp(
    r'^(?:남|여|남성|여성|남자|여자|m|f)$',
    caseSensitive: false,
  );
  static final RegExp _ageValuePattern = RegExp(r'^\d{1,3}세$');
  static final RegExp _bareNumberValuePattern = RegExp(r'^\d{1,3}$');
  // 이름·주소처럼 한글로 적힌 값이다. "HP", "TEL" 같은 영문 표기는 값으로 세지 않는다.
  static final RegExp _wordValuePattern = RegExp(r'[가-힣]{2,}');
  // 나이·성별은 "75세/남", "75세(남)", "(남/75세)", "여 68세"처럼 어느 순서로 인쇄되어도 찾는다.
  static final RegExp _ageGenderPattern = RegExp(
    r'(?<!\d)(?:만\s*)?\d{1,3}\s*세\s*[/·,\s(-]?\s*(?:남|여)(?:성)?(?![가-힣])'
    r'|(?<![가-힣])(?:남|여)(?:성)?\s*[/·,\s(-]?\s*(?:만\s*)?\d{1,3}\s*세',
  );
  // 뒷자리가 별표로 가려졌거나 긴 줄표로 이어진 주민등록번호도 포함한다.
  static final RegExp _residentNumberPattern = RegExp(
    r'(?<!\d)\d{6}\s*[-–—~ ]?\s*[1-8][\d*]{6}(?![\d*])',
  );
  static final RegExp _phonePattern = RegExp(
    r'(?<!\d)(?:01[016789]|0[2-6][1-5]?)\s*[-.) ]?\s*'
    r'\d{3,4}\s*[-. ]?\s*\d{4}(?!\d)',
  );
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp prescriptionDateLabelPattern = RegExp(
    r'(조제\s*일자|조제\s*일|처방\s*일자|처방\s*일)',
  );

  // 함수이름: PrescriptionPrivacyFilter
  // 함수역할: 개인정보 라벨과 식별자 패턴으로 로컬 OCR 문구를 검사하는 무상태 필터를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PrescriptionPrivacyFilter: 초기화된 인스턴스.
  const PrescriptionPrivacyFilter();

  // 함수이름: containsSensitiveInformation
  // 함수역할: 한 줄에 개인정보 라벨이나 직접 식별자 패턴이 포함됐는지 판별한다.
  // 매개변수:
  // - text (String): 기기 OCR이 인식한 한 줄
  // 반환값:
  // - 민감정보가 포함되면 true
  bool containsSensitiveInformation(String text) {
    return _sensitiveLabelPattern.hasMatch(text) ||
        _ageGenderPattern.hasMatch(text) ||
        _residentNumberPattern.hasMatch(text) ||
        _phonePattern.hasMatch(text) ||
        _emailPattern.hasMatch(text);
  }

  // Function Name: sensitiveLineFlags
  // Description: Track sensitive label runs and following value rows, stopping pending masking at medication-like rows.
  // Parameters: lines (List<String>): OCR lines in recognition order.
  // Returns: List<bool>: sensitivity flag aligned with each input line.
  List<bool> sensitiveLineFlags(List<String> lines) {
    final flags = <bool>[];
    var pendingValueLines = 0;
    var pendingNeutralValues = 0;
    var nextLineMayJoinValues = false;
    var index = 0;
    while (index < lines.length) {
      if (_isLabelOnlyLine(lines[index])) {
        // [1단계]: 연속된 라벨 줄을 한 묶음으로 모아 개인정보 라벨 수와 나이·성별 라벨 수를 센다.
        var runEnd = index;
        var sensitiveLabels = 0;
        var neutralLabels = 0;
        var lastLineLabels = 0;
        while (runEnd < lines.length && _isLabelOnlyLine(lines[runEnd])) {
          final sensitiveCount = _sensitiveLabelCount(lines[runEnd]);
          final neutralCount = _neutralLabelPattern
              .allMatches(lines[runEnd])
              .length;
          sensitiveLabels += sensitiveCount;
          neutralLabels += neutralCount;
          lastLineLabels = sensitiveCount + neutralCount;
          runEnd += 1;
        }
        // [2단계]: 개인정보 라벨이 있거나 이미 값을 기다리는 중이면 묶음 전체를 가리고 라벨 수만큼 값 줄을 기다린다.
        final arms = sensitiveLabels > 0 || pendingValueLines > 0;
        for (; index < runEnd; index += 1) {
          flags.add(arms);
        }
        if (arms) {
          pendingValueLines += sensitiveLabels + neutralLabels;
          pendingNeutralValues += neutralLabels;
          nextLineMayJoinValues = lastLineLabels > 1;
        }
        continue;
      }

      final text = lines[index];
      index += 1;
      if (pendingValueLines > 0 && _looksLikeMedicationRow(text)) {
        pendingValueLines = 0;
      }
      flags.add(pendingValueLines > 0 || containsSensitiveInformation(text));
      if (pendingValueLines > 0) {
        // [3단계]: 이 값 줄이 채운 라벨 수만큼 기다리는 수를 줄인다.
        final values = _valueCountsInLine(
          text,
          joinedRow: nextLineMayJoinValues,
        );
        final neutralValues = values.ageAndGender < pendingNeutralValues
            ? values.ageAndGender
            : pendingNeutralValues;
        final consumed = neutralValues + values.others;
        pendingNeutralValues -= neutralValues;
        pendingValueLines -= consumed < 1 ? 1 : consumed;
      }
      if (pendingValueLines <= 0) {
        pendingValueLines = 0;
        pendingNeutralValues = 0;
      }
      nextLineMayJoinValues = false;
    }
    return flags;
  }

  // Function Name: _sensitiveLabelCount
  // Description: Count occurrences of recognized sensitive labels.
  // Parameters: text (String): OCR line.
  // Returns: int: matching label count.
  int _sensitiveLabelCount(String text) {
    return _sensitiveLabelPattern.allMatches(text).length;
  }

  // Function Name: _isLabelOnlyLine
  // Description: Check whether a line contains only sensitive/neutral labels and separators.
  // Parameters: text (String): OCR line.
  // Returns: bool: true only when a recognized label exists and no value text remains.
  bool _isLabelOnlyLine(String text) {
    if (!_sensitiveLabelPattern.hasMatch(text) &&
        !_neutralLabelPattern.hasMatch(text)) {
      return false;
    }
    return text
        .replaceAll(_sensitiveLabelPattern, ' ')
        .replaceAll(_neutralLabelPattern, ' ')
        .replaceAll(_labelSeparatorPattern, '')
        .isEmpty;
  }

  // Function Name: _looksLikeMedicationRow
  // Description: Detect dosage units or medication-form cues that end pending personal-value masking.
  // Parameters: text (String): OCR line.
  // Returns: bool: medication-row pattern match.
  bool _looksLikeMedicationRow(String text) {
    return _medicationRowPattern.hasMatch(text);
  }

  // Function Name: _valueCountsInLine
  // Description: Estimate neutral age/gender values and other personal-value groups for consuming pending label rows.
  // Parameters: text (String): OCR value line; joinedRow (bool): multiple labels may share one value row.
  // Returns: ({int ageAndGender, int others}): estimated value-group counts.
  ({int ageAndGender, int others}) _valueCountsInLine(
    String text, {
    required bool joinedRow,
  }) {
    var identifiers = 0;
    // 값 줄에 다시 적힌 라벨 낱말은 값으로 세지 않는다.
    var remaining = text.replaceAll(_sensitiveLabelPattern, ' ');
    // 날짜의 끝자리가 지역번호로 읽히지 않도록 생년월일을 연락처보다 먼저 센다.
    for (final pattern in [
      _residentNumberPattern,
      _birthDateValuePattern,
      _phonePattern,
      _emailPattern,
    ]) {
      identifiers += pattern.allMatches(remaining).length;
      remaining = remaining.replaceAll(pattern, ' ');
    }
    var ageAndGender = 0;
    var bareNumbers = 0;
    var words = 0;
    var otherTokens = 0;
    for (final token in remaining.split(_labelSeparatorPattern)) {
      if (token.isEmpty) {
        continue;
      }
      if (_genderValuePattern.hasMatch(token) ||
          _ageValuePattern.hasMatch(token)) {
        ageAndGender += 1;
      } else if (_bareNumberValuePattern.hasMatch(token)) {
        bareNumbers += 1;
      } else if (_wordValuePattern.hasMatch(token)) {
        words += 1;
      } else {
        otherTokens += 1;
      }
    }
    final onlyOneNumber =
        bareNumbers == 1 && identifiers + words + otherTokens == 0;
    final nameWithNumber =
        joinedRow && bareNumbers == 1 && words == 1 && otherTokens == 0;
    if (bareNumbers == 1 &&
        (ageAndGender > 0 || onlyOneNumber || nameWithNumber)) {
      ageAndGender += 1;
      bareNumbers = 0;
    }
    final hasOthers = identifiers + words + otherTokens + bareNumbers > 0;
    return (
      ageAndGender: ageAndGender,
      others: joinedRow
          ? identifiers + (words > 0 ? 1 : 0)
          : (hasOthers ? 1 : 0),
    );
  }

  // 함수이름: maskInlineIdentifiers
  // 함수역할: 문자열 안의 주민등록번호·연락처·이메일을 원문이 남지 않도록 치환한다.
  // 매개변수:
  // - text (String): 정리할 OCR 문자열
  // 반환값:
  // - 직접 식별자가 대체 문구로 바뀐 문자열
  String maskInlineIdentifiers(String text) {
    return text
        .replaceAll(_residentNumberPattern, '[주민번호 제거]')
        .replaceAll(_phonePattern, '[연락처 제거]')
        .replaceAll(_emailPattern, '[이메일 제거]');
  }
}
