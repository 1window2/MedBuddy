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
    var maskFollowingLine = false;

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) {
          continue;
        }
        final sensitive =
            maskFollowingLine ||
            _privacyFilter.containsSensitiveInformation(text);
        maskFollowingLine =
            !maskFollowingLine && _privacyFilter.shouldMaskFollowingLine(text);
        final region = _toRegion(
          text: sensitive ? '' : _privacyFilter.maskInlineIdentifiers(text),
          bounds: line.boundingBox,
          imageSize: imageSize,
          category: sensitive ? 'sensitive_info' : _categoryForSafeText(text),
        );
        if (region != null && regions.length < _maximumPreviewRegions) {
          regions.add(region);
        }
        if (!sensitive) {
          final maskedLine = _privacyFilter.maskInlineIdentifiers(text).trim();
          if (maskedLine.isNotEmpty) {
            safeLines.add(maskedLine);
          }
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
// - 개인정보 라벨과 값이 서로 다른 줄로 인식된 경우 다음 줄도 제거하도록 알려준다.
// - 안전한 복약 문구에 섞인 직접 식별자만 대체 문구로 치환한다.
class PrescriptionPrivacyFilter {
  static final RegExp _sensitiveLabelPattern = RegExp(
    r'(환자\s*(명|성명|이름|번호|정보)|성\s*명|주민\s*(등록)?\s*번호|'
    r'생년\s*월일|주소|전화\s*번호|연락처|휴대폰|보험\s*번호|'
    r'차트\s*번호|의무\s*기록\s*번호)',
    caseSensitive: false,
  );
  static final RegExp _standaloneSensitiveLabelPattern = RegExp(
    r'^\s*(환자\s*(명|성명|이름|번호|정보)|성\s*명|주민\s*(등록)?\s*번호|'
    r'생년\s*월일|주소|전화\s*번호|연락처|휴대폰|보험\s*번호|'
    r'차트\s*번호|의무\s*기록\s*번호)\s*[:：]?\s*$',
    caseSensitive: false,
  );
  static final RegExp _ageGenderPattern = RegExp(
    r'(?<!\d)(?:만\s*)?\d{1,3}\s*세\s*[/·,\s-]?\s*(?:남|여)(?:성)?(?![가-힣])',
  );
  static final RegExp _residentNumberPattern = RegExp(
    r'(?<!\d)\d{6}\s*[- ]?\s*[1-8]\d{6}(?!\d)',
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

  // 함수이름: shouldMaskFollowingLine
  // 함수역할: 개인정보 라벨만 단독으로 인식돼 실제 값이 다음 줄에 있을 가능성을 판별한다.
  // 매개변수:
  // - text (String): 기기 OCR이 인식한 한 줄
  // 반환값:
  // - 다음 줄까지 제거해야 하면 true
  bool shouldMaskFollowingLine(String text) {
    return _standaloneSensitiveLabelPattern.hasMatch(text);
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
