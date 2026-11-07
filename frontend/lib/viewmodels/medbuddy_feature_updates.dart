import 'package:flutter/foundation.dart';

// 파일명: medbuddy_feature_updates.dart
// 역할: 앱 전역 ViewModel의 변경 알림을 기능 단위로 분리한다.

// 클래스명: MedBuddyFeature
// 역할: 앱의 기능별 변경 구독 대상을 구분한다.
// 주요 책임: 처방·저장 약·일정·알림·건강 추천·사용자 설정의 갱신 범위를 지정한다.
// 속성: prescription/savedMedication/schedule/reminder/healthRecommendation/userSetting: 기능 식별값.
enum MedBuddyFeature {
  prescription,
  savedMedication,
  schedule,
  reminder,
  healthRecommendation,
  userSetting,
}

// 클래스명: MedBuddyFeatureUpdates
// 역할: 기능별 변경 순번과 구독 알림을 관리한다.
// 주요 책임: markChanged 호출마다 순번을 증가시키고 리스너를 알린다.
// 속성: _revision (int): 변경 순번; revision: 읽기 전용 공개 값.
class MedBuddyFeatureUpdates extends ChangeNotifier {
  int _revision = 0;

  // 함수이름: revision
  // 함수역할: 해당 기능에서 발생한 변경 알림의 누적 횟수를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - int: 해당 기능에서 발생한 변경 알림의 누적 횟수를 제공한다.
  int get revision => _revision;

  // 함수이름: markChanged
  // 함수역할: 해당 기능의 상태가 바뀌었음을 구독 화면에 알린다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void markChanged() {
    _revision += 1;
    notifyListeners();
  }
}
