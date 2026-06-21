// 파일명: health_recommendation_entity.dart
// 역할: 건강 관리 추천 API 응답을 화면에서 사용할 모델로 변환한다.

// 클래스명: HealthRecommendation
// 역할: 약 조합 기반 건강 관리 추천 내용을 보관한다.
// 주요 책임:
// - 백엔드 AI 추천 응답을 식사, 운동, 주의사항 필드로 정규화한다.
// - 추천 생성에 사용된 약 이름 목록을 보관한다.
class HealthRecommendation {
  final String dietRecommendation;
  final String exerciseRecommendation;
  final List<String> cautionItems;
  final List<String> medicationNames;

  const HealthRecommendation({
    required this.dietRecommendation,
    required this.exerciseRecommendation,
    required this.cautionItems,
    this.medicationNames = const [],
  });

  factory HealthRecommendation.fromJson(Map<String, dynamic> json) {
    return HealthRecommendation(
      dietRecommendation: _readString(
        json['diet_recommendation'] ?? json['dietRecommendation'],
        '식사 추천 정보를 불러오지 못했습니다.',
      ),
      exerciseRecommendation: _readString(
        json['exercise_recommendation'] ?? json['exerciseRecommendation'],
        '운동 추천 정보를 불러오지 못했습니다.',
      ),
      cautionItems:
          _readStringList(json['caution_items'] ?? json['cautionItems']),
      medicationNames: _readStringList(
        json['medication_names'] ?? json['medicationNames'],
      ),
    );
  }

  static String _readString(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
