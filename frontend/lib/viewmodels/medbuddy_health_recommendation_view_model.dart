part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_health_recommendation_view_model.dart
// 역할: 복용 약 조합 기반 건강관리 추천 조회 상태를 관리한다.

// 클래스명: MedBuddyHealthRecommendationViewModel
// 역할: 복용 약 조합에 대한 건강 추천 조회 상태를 확장한다.
// 주요 책임:
// - 언어별 추천 Control을 호출하고 로딩·결과·실패 안내를 건강 추천 구독 화면에 반영한다.
extension MedBuddyHealthRecommendationViewModel on MedBuddyViewModel {
  // 함수이름: fetchHealthRecommendation
  // 함수역할: 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 서버에서 가져온다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> fetchHealthRecommendation() async {
    _isHealthRecommendationLoading = true;
    _healthRecommendation = null;
    _statusMessage = _isEnglishSetting
        ? 'Loading health recommendations.'
        : '건강 관리 추천을 불러오는 중입니다.';
    _notifyViewModelListeners(MedBuddyFeature.healthRecommendation);

    try {
      final healthRecommendation = await checkHealthRecommendation
          .requestHealthRecommendation(language: userSetting.language);
      _healthRecommendation = healthRecommendation;
      _statusMessage = _isEnglishSetting
          ? 'Health recommendations loaded.'
          : '건강 관리 추천을 불러왔습니다.';
    } on StateError {
      _statusMessage = _isEnglishSetting
          ? 'Could not create recommendations. Check that you have active medications.'
          : '건강 관리 추천을 만들지 못했습니다. 현재 복용 중인 약이 있는지 확인해주세요.';
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not load health recommendations.'
          : '건강 관리 추천을 불러오지 못했습니다.';
    } finally {
      _isHealthRecommendationLoading = false;
      _notifyViewModelListeners(MedBuddyFeature.healthRecommendation);
    }
  }
}
