// 파일명: recognized_text_region_entity.dart
// 역할: 처방전 이미지에서 OCR이 복약 정보로 인식한 위치를 표현한다.

// 클래스명: RecognizedTextRegion
// 역할: 인식 문구와 0~1000 정규화 좌표를 화면에 전달한다.
// 주요 책임:
// - 백엔드 OCR 응답의 위치 좌표를 안전한 범위로 정규화한다.
// - 원본 이미지 위에 표시할 인식 영역 또는 개인정보 마스킹 좌표를 보관한다.
// 속성:
// - category: 조제일자 또는 약품 행을 구분하는 영역 종류
// - text: 해당 영역에서 인식한 복약 관련 문구
// - box2d: ymin, xmin, ymax, xmax 순서의 정규화 좌표
class RecognizedTextRegion {
  final String category;
  final String text;
  final List<double> box2d;

  const RecognizedTextRegion({
    required this.category,
    required this.text,
    required this.box2d,
  });

  bool get isValid {
    return box2d.length == 4 && box2d[0] < box2d[2] && box2d[1] < box2d[3];
  }

  bool get isSensitive => category == 'sensitive_info';

  // 함수이름: fromJson
  // 함수역할:
  // - OCR 영역 JSON을 좌표 범위가 검증된 화면 엔티티로 변환한다.
  // 매개변수:
  // - json: category, text, box_2d 필드가 포함된 OCR 영역 JSON
  // 반환값:
  // - 좌표가 유효하면 RecognizedTextRegion, 그렇지 않으면 null
  static RecognizedTextRegion? fromJson(Map<String, dynamic> json) {
    final rawBox = json['box_2d'] ?? json['box2d'];
    if (rawBox is! List || rawBox.length != 4) {
      return null;
    }
    final normalizedBox = rawBox
        .map((value) => double.tryParse(value.toString()))
        .toList(growable: false);
    if (normalizedBox.any((value) => value == null)) {
      return null;
    }
    final box = normalizedBox
        .cast<double>()
        .map((value) => value.clamp(0, 1000).toDouble())
        .toList(growable: false);
    final region = RecognizedTextRegion(
      category: json['category']?.toString().trim() ?? '',
      text: json['text']?.toString().trim() ?? '',
      box2d: box,
    );
    return region.isValid ? region : null;
  }

  // 함수이름: fromJsonList
  // 함수역할:
  // - OCR 영역 목록에서 유효한 항목만 화면 엔티티 목록으로 변환한다.
  // 매개변수:
  // - value: 백엔드가 반환한 recognized_regions 값
  // 반환값:
  // - 유효한 OCR 인식 영역 목록
  static List<RecognizedTextRegion> fromJsonList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => fromJson(Map<String, dynamic>.from(item)))
        .whereType<RecognizedTextRegion>()
        .toList(growable: false);
  }
}
