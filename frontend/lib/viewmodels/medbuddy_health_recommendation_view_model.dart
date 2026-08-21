part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_health_recommendation_view_model.dart
// 역할: 복용 약 조합 기반 건강관리 추천 조회 상태를 관리한다.

// 확장명: MedBuddyHealthRecommendationViewModel
// 역할: MedBuddyViewModel의 해당 기능 상태 전이와 Control 호출을 한곳에 모은다.
extension MedBuddyHealthRecommendationViewModel on MedBuddyViewModel {
  // 함수명: fetchHealthRecommendation
  // 함수역할:
  // - 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchHealthRecommendation() async {
    _isHealthRecommendationLoading = true;
    _healthRecommendation = null;
    _statusMessage = _isEnglishSetting
        ? 'Loading health recommendations.'
        : '건강 관리 추천을 불러오는 중입니다.';
    _notifyViewModelListeners();

    try {
      final healthRecommendation = await checkHealthRecommendation
          .requestHealthRecommendation(language: userSetting.language);
      _healthRecommendation = healthRecommendation;
      _statusMessage = _isEnglishSetting
          ? 'Health recommendations loaded.'
          : '건강 관리 추천을 불러왔습니다.';
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not load health recommendations.'
          : '건강 관리 추천을 불러오지 못했습니다.';
    } finally {
      _isHealthRecommendationLoading = false;
      _notifyViewModelListeners();
    }
  }
}
