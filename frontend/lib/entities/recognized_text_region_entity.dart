// 파일명: recognized_text_region_entity.dart
// 역할: 처방전 이미지에서 OCR이 복약 정보로 인식한 위치를 표현한다.

// 클래스명: RecognizedTextRegion
// 역할: 인식 문구와 0~1000 정규화 좌표를 화면에 전달한다.
// 주요 책임:
// - 기기 내 OCR이 만든 위치 좌표의 유효성을 판별한다.
// - 원본 이미지 위에 표시할 인식 영역 또는 개인정보 마스킹 좌표를 보관한다.
// 속성:
// - category: 약품 정보 또는 개인정보 마스킹을 구분하는 영역 종류
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

  bool get isMedication =>
      category == 'medication_name' || category == 'medication_row';

  bool get isVisibleInPreview => isSensitive || isMedication;
}
