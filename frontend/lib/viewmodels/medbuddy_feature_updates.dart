import 'package:flutter/foundation.dart';

// 파일명: medbuddy_feature_updates.dart
// 역할: 앱 전역 ViewModel의 변경 알림을 기능 단위로 분리한다.

enum MedBuddyFeature {
  prescription,
  savedMedication,
  schedule,
  reminder,
  healthRecommendation,
  userSetting,
}

// 클래스명: MedBuddyFeatureUpdates
// 역할: 특정 기능을 사용하는 화면만 다시 그릴 수 있도록 변경 횟수를 알린다.
class MedBuddyFeatureUpdates extends ChangeNotifier {
  int _revision = 0;

  int get revision => _revision;

  // 함수명: markChanged
  // 역할:
  // - 해당 기능의 상태가 바뀌었음을 구독 화면에 알린다.
  void markChanged() {
    _revision += 1;
    notifyListeners();
  }
}
