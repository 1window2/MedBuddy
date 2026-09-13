// 파일명: recognized_text_region_entity.dart
// 역할: 처방전 이미지에서 OCR이 복약 정보로 인식한 위치를 표현한다.

// 클래스명: RecognizedTextRegion
// 역할: 인식 문구와 0~1000 정규화 좌표를 화면에 전달한다.
// 주요 책임:
// - 기기 내 OCR이 만든 위치 좌표의 유효성을 판별한다.
// - 원본 이미지 위에 표시할 인식 영역 또는 개인정보 마스킹 좌표를 보관한다.
// 속성:
// - category (String): 약품 정보 또는 개인정보 마스킹을 구분하는 영역 종류
// - text (String): 해당 영역에서 인식한 복약 관련 문구
// - box2d (List<double>): ymin, xmin, ymax, xmax 순서의 정규화 좌표
class RecognizedTextRegion {
  final String category;
  final String text;
  final List<double> box2d;

  // 함수이름: RecognizedTextRegion
  // 함수역할: 인식 영역의 종류와 문구를 ymin·xmin·ymax·xmax 순서의 정규화 좌표와 함께 보존한다.
  // 매개변수:
  // - category (String): 약품·날짜·개인정보 등 OCR 영역 분류
  // - text (String): 인식·정규화·마스킹·읽기에 사용할 문구
  // - box2d (List<double>): ymin·xmin·ymax·xmax 순서의 0~1000 좌표
  // 반환값:
  // - RecognizedTextRegion: 초기화된 인스턴스.
  const RecognizedTextRegion({
    required this.category,
    required this.text,
    required this.box2d,
  });

  // 함수이름: isValid
  // 함수역할: 좌표가 네 개이며 위쪽이 아래쪽보다, 왼쪽이 오른쪽보다 앞서는 양의 크기 영역인지 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 좌표가 네 개이며 위쪽이 아래쪽보다, 왼쪽이 오른쪽보다 앞서는 양의 크기 영역인지 판정한다.
  bool get isValid {
    return box2d.length == 4 && box2d[0] < box2d[2] && box2d[1] < box2d[3];
  }

  // 함수이름: isSensitive
  // 함수역할: 개인정보 마스킹 대상으로 분류된 영역인지 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 개인정보 마스킹 대상으로 분류된 영역인지 판정한다.
  bool get isSensitive => category == 'sensitive_info';

  // 함수이름: isMedication
  // 함수역할: 약 이름 또는 약품 행으로 분류된 영역인지 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 약 이름 또는 약품 행으로 분류된 영역인지 판정한다.
  bool get isMedication =>
      category == 'medication_name' || category == 'medication_row';

  // 함수이름: isVisibleInPreview
  // 함수역할: 개인정보 마스킹 또는 약품 강조에 해당하는 영역만 미리보기 표시 대상으로 선택한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 개인정보 마스킹 또는 약품 강조에 해당하는 영역만 미리보기 표시 대상으로 선택한다.
  bool get isVisibleInPreview => isSensitive || isMedication;
}
