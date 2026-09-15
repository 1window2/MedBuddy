import 'package:flutter/foundation.dart';

// 파일명: medbuddy_feature_updates.dart
// 역할: 앱 전역 ViewModel의 변경 알림을 기능 단위로 분리한다.

// 클래스명: MedBuddyFeature
// 역할: 처방전·저장 약·일정·설정 등 상태 변경을 구독할 기능 영역을 구분한다.
// 주요 책임:
// - 관심 기능만 갱신하는 알림 채널의 키로 사용한다.
// 비고:
// - 파일명: medbuddy_feature_updates.dart
enum MedBuddyFeature {
  prescription,
  savedMedication,
  schedule,
  reminder,
  healthRecommendation,
  userSetting,
}

// 클래스명: MedBuddyFeatureUpdates
// 역할: 특정 기능의 변경 알림과 수정 횟수를 제공한다.
// 주요 책임:
// - 수정 카운터를 증가시키고 해당 기능을 구독한 화면만 갱신하도록 알린다.
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
