import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../entities/recognized_text_region_entity.dart';

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
// 역할: 이미지 입력 Control이 사용할 로컬 인식·마스킹 계약이다.
// 주요 책임:
// - ML Kit 구현에 의존하지 않고 파일 경로에서 비식별 텍스트와 미리보기 영역을 얻도록 한다.
abstract interface class PrescriptionLocalOcrBoundary {
  // 함수이름: recognizeAndMask
  // 함수역할: 로컬 처방전 파일에서 개인정보를 제거한 텍스트와 미리보기 영역을 얻는 비동기 인식 계약을 제공한다.
  // 매개변수:
  // - imagePath (String): 기기에서 읽을 원본 이미지 경로
  // 반환값:
  // - Future<LocalPrescriptionOcrResult>: 로컬 처방전 파일에서 개인정보를 제거한 텍스트와 미리보기 영역을 얻는 비동기 인식 계약을 제공한다.
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath);
}

// 클래스명: PrescriptionLocalOcrService
// 역할: 기기 내 ML Kit로 처방전 텍스트와 위치를 읽고 민감정보를 제거한다.
// 주요 책임:
// - 한글 OCR을 외부 서버 전송 전에 수행한다.
// - 환자 식별 라벨과 주민번호·연락처·이메일 패턴을 민감정보로 분류한다.
// - 민감정보 줄은 서버 전송 텍스트에서 제외하고 미리보기에는 마스킹 영역만 남긴다.
// 속성:
// - _textRecognizer (TextRecognizer): 기기 내 한글 OCR 인식기
// - _privacyFilter (PrescriptionPrivacyFilter): OCR 개인정보 라벨·식별자 제거 규칙
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

  // 함수이름: recognizeAndMask
  // 함수역할: 이미지에서 텍스트와 좌표를 읽고 민감정보가 제거된 결과를 반환한다.
  // 매개변수:
  // - imagePath (String): 카메라 또는 갤러리에서 선택한 로컬 이미지 경로
  // 반환값:
  // - 비식별 OCR 텍스트와 화면 표시 영역
  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    final imageSize = await _readImageSize(imagePath);
    final safeLines = <String>[];
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
          safeLines.add(maskedLine);
        }
      }
    }

    final maskedText = safeLines.join('\n').trim();
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

// 클래스명: PrescriptionPrivacyFilter
// 역할: 기기에서 인식한 처방전 문자열 중 외부 전송이 금지된 개인정보를 판별한다.
// 주요 책임:
// - 개인정보 라벨과 주민등록번호·연락처·이메일 패턴을 탐지한다.
// - 개인정보 라벨과 값이 서로 다른 줄로 인식된 경우 라벨 수만큼 뒤따르는 값 줄도 제거하도록 알려준다.
// - 값 자리에 약 행이 온 경우에는 약 행을 값으로 보지 않아 약이 분석에서 빠지지 않게 한다.
// - 안전한 복약 문구에 섞인 직접 식별자만 대체 문구로 치환한다.
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

  // 함수이름: sensitiveLineFlags
  // 함수역할: 인식한 줄 순서대로 개인정보 여부를 판정한다. 값 없이 라벨만 있는 줄이 이어지면 그 라벨 수만큼 뒤따르는 줄도 값으로 보고 가린다.
  // - 라벨 줄 묶음에 개인정보 라벨이 하나라도 있으면 함께 나열된 나이·성별 라벨도 값 줄 수에 포함한다.
  // - 값 줄 하나에 나이·성별 값이 함께 적혀 있으면 기다리던 나이·성별 라벨 수 안에서 그만큼 더 줄인다.
  // - 한 줄에 라벨이 여럿인 머리행 바로 다음 줄은 값도 한 줄에 붙어 인식됐을 수 있으므로 그 줄에 담긴 값 수만큼 한꺼번에 줄인다.
  // - 값 자리에 약 행이 오면 라벨과 값의 짝이 깨진 것이므로 남은 수를 버리고 약 행은 가리지 않는다.
  // 매개변수: lines: 공백을 정리한 OCR 줄 목록. 반환값: 각 줄을 가려야 하는지 나타내는 같은 길이의 목록.
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

  // 함수이름: _sensitiveLabelCount
  // 함수역할: 한 줄에 들어 있는 개인정보 라벨 수를 센다. "수진자 성명"처럼 이어 쓴 라벨은 하나로 센다.
  // 매개변수:
  // - text (String): 기기 OCR이 인식한 한 줄
  // 반환값:
  // - int: 개인정보 라벨 수.
  int _sensitiveLabelCount(String text) {
    return _sensitiveLabelPattern.allMatches(text).length;
  }

  // 함수이름: _isLabelOnlyLine
  // 함수역할: 개인정보 라벨과 나이·성별 라벨, 구분 기호만으로 이루어져 값이 없는 줄인지 판별한다.
  // 매개변수:
  // - text (String): 기기 OCR이 인식한 한 줄
  // 반환값:
  // - bool: 라벨이 하나 이상 있고 라벨 외의 글자가 없으면 true.
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

  // 함수이름: _looksLikeMedicationRow
  // 함수역할: 용량·횟수 단위나 제형 표기가 있어 환자 정보 값이 아니라 약 행으로 볼 수 있는 줄인지 판별한다.
  // 매개변수:
  // - text (String): 기기 OCR이 인식한 한 줄
  // 반환값:
  // - bool: 약 행으로 보이면 true.
  bool _looksLikeMedicationRow(String text) {
    return _medicationRowPattern.hasMatch(text);
  }

  // 함수이름: _valueCountsInLine
  // 함수역할: 값 줄 하나에 라벨 몇 개의 값이 들어 있는지를 나이·성별 값과 그 밖의 값으로 나눠 센다.
  // - 성별 낱말과 "75세"는 나이·성별 값으로 센다. 단위 없는 1~3자리 숫자는 줄 전체가 그 숫자이거나, 성별·나이 값과 함께 있거나, 머리행 다음 줄에서 단어 하나 뒤에 붙은 경우에만 나이로 본다(주소의 번지 제외).
  // - 보통은 그 밖의 값을 줄당 하나로 센다. 머리행 바로 다음 줄(joinedRow)에서는 주민등록번호·생년월일·연락처·이메일을 각각 하나로, 한글로 적힌 나머지(이름·주소)를 묶어 하나로 센다.
  // - 확실한 값만 세므로 덜 셀 수는 있어도 더 세지는 않는다. 덜 세면 다음 줄을 더 가릴 뿐 개인정보가 남지 않는다.
  // 매개변수:
  // - text (String): 값이 들어 있는 OCR 한 줄
  // - joinedRow (bool): 한 줄에 라벨이 여럿인 머리행 바로 다음 줄인지 여부
  // 반환값:
  // - ({int ageAndGender, int others}): 나이·성별 값 수와 그 밖의 값 수.
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
