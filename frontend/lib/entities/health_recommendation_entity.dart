// 파일명: health_recommendation_entity.dart
// 역할: 건강 관리 추천 API 응답을 화면에서 사용할 모델로 변환한다.

// 클래스명: HealthRecommendation
// 역할: 약 조합 기반 건강 관리 추천 내용을 보관한다.
// 주요 책임:
// - 백엔드 AI 추천 응답을 식사, 운동, 주의사항 필드로 정규화한다.
// - 추천 생성에 사용된 약 이름 목록을 보관한다.
// 속성:
// - dietRecommendation (String): 복용 약 조합 기반 식사 추천
// - exerciseRecommendation (String): 복용 약 조합 기반 운동 추천
// - cautionItems (List<String>): 추천과 함께 표시할 주의 항목 목록
// - medicationNames (List<String>): 알림·추천에 사용할 약 표시 이름 목록
class HealthRecommendation {
  final String dietRecommendation;
  final String exerciseRecommendation;
  final List<String> cautionItems;
  final List<String> medicationNames;

  // 함수이름: HealthRecommendation
  // 함수역할: 복용 약 조합에 대한 식사·운동 추천, 주의 항목과 추천에 사용된 약 이름 목록을 보존한다.
  // 매개변수:
  // - dietRecommendation (String): 복용 약 조합 기반 식사 추천
  // - exerciseRecommendation (String): 복용 약 조합 기반 운동 추천
  // - cautionItems (List<String>): 추천과 함께 표시할 주의 항목 목록
  // - medicationNames (List<String>): 알림·추천에 사용할 약 표시 이름 목록
  // 반환값:
  // - HealthRecommendation: 초기화된 인스턴스.
  const HealthRecommendation({
    required this.dietRecommendation,
    required this.exerciseRecommendation,
    required this.cautionItems,
    this.medicationNames = const [],
  });

  // 함수이름: HealthRecommendation.fromJson
  // 함수역할: 식사·운동·주의 항목을 현재 및 구형 필드명에서 읽고 누락된 추천 문장은 요청 언어의 안내문으로 대체한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - HealthRecommendation: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
  factory HealthRecommendation.fromJson(
    Map<String, dynamic> json, {
    String language = 'ko',
  }) {
    final isEnglish = language.trim().toLowerCase().startsWith('en');
    return HealthRecommendation(
      dietRecommendation: _readString(
        json['diet_recommendation'] ?? json['dietRecommendation'],
        isEnglish
            ? 'Diet recommendation is unavailable.'
            : '식사 추천 정보를 불러오지 못했습니다.',
      ),
      exerciseRecommendation: _readString(
        json['exercise_recommendation'] ?? json['exerciseRecommendation'],
        isEnglish
            ? 'Exercise recommendation is unavailable.'
            : '운동 추천 정보를 불러오지 못했습니다.',
      ),
      cautionItems: _readStringList(
        json['caution_items'] ?? json['cautionItems'],
      ),
      medicationNames: _readStringList(
        json['medication_names'] ?? json['medicationNames'],
      ),
    );
  }

  // 함수이름: _readString
  // 함수역할: 공백을 정리한 값이 비어 있으면 호출자가 지정한 대체 문자열을 사용한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // - fallback (String): 값이 없거나 해석 불가할 때 사용할 대체값
  // 반환값:
  // - String: 공백 정리한 유효 문자열 또는 지정한 대체 문자열.
  static String _readString(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  // 함수이름: _readStringList
  // 함수역할: 배열 항목을 공백 정리한 문자열로 바꾸고 빈 항목을 제외하며 배열이 아닌 입력은 빈 목록으로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - List<String>: 공백과 빈 항목을 정리한 문자열 목록; 배열이 아니면 빈 목록.
  static List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map(/* 함수이름: map 콜백
         * 함수역할: 건강 추천의 목록 항목을 공백 정리한 표시 문자열로 바꾼다.
         * 매개변수:
         * - item (dynamic): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 항목의 공백 정리된 문자열.
         */(item) => item.toString().trim())
        .where(/* 함수이름: where 콜백
         * 함수역할: 내용이 있는 건강 추천 문자열만 남긴다.
         * 매개변수:
         * - item (String): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 문자열이 비어 있지 않으면 true.
         */(item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
