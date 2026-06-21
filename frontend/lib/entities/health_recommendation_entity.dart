// 파일명: health_recommendation_entity.dart
// 역할: 건강 추천 관리 기능을 위한 추천 문구 모델을 정의한다.

// 클래스명: HealthRecommendation
// 역할: 향후 AI 또는 API 기반 건강 추천 문구를 앱 내부에서 보관한다.
// 주요 책임:
// - 건강 추천 텍스트를 단일 모델로 관리한다.
// - 후속 건강 추천 화면에서 사용할 반환 메서드를 제공한다.
class HealthRecommendation {
  final String recommendationText;

  const HealthRecommendation({this.recommendationText = ''});

  // 함수명: getHealthRecommendation
  // 함수역할:
  // - 저장된 건강 추천 문구를 반환한다.
  // 반환값:
  // - 건강 추천 텍스트
  String getHealthRecommendation() {
    return recommendationText;
  }
}
