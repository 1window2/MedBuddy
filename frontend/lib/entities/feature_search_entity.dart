// 파일명: feature_search_entity.dart
// 역할: 기능 검색의 허용된 이동 목적지와 한국어·영어 검색 항목을 정의한다.

// 클래스명: AppFeature
// 역할: 검색 결과가 실행할 수 있는 화면 이동만 열거한다. 데이터 변경 명령은 포함하지 않는다.
enum AppFeature {
  manualMedication,
  prescription,
  pillIdentification,
  schedule,
  asNeeded,
  medicationCabinet,
  medicationHistory,
  historySharing,
  caregiverLink,
  caregiverSchedule,
  chat,
  nearbyPharmacy,
  nearbyHospital,
  healthRecommendation,
  notificationInbox,
  notifications,
  notificationReception,
  defaultTimes,
  notificationPrivacy,
  fontSize,
  language,
  timeFormat,
  readingSpeed,
  homeSchedule,
  homeWidget,
  account,
  dataUse,
}

// 클래스명: FeatureSearchEntry
// 역할: 표시 이름·위치·동의어·의도별 단어 조합을 보관한다. 사용자 정보는 저장하지 않는다.
class FeatureSearchEntry {
  final AppFeature feature;
  final String ko;
  final String en;
  final String pathKo;
  final String pathEn;
  final List<String> phrases;
  final List<List<String>> concepts;
  final int conceptBoost;

  // 함수이름: FeatureSearchEntry
  // 함수역할: 정적 기능 검색 항목을 만든다. concepts의 각 그룹은 같은 의미의 단어들이다.
  const FeatureSearchEntry(
    this.feature,
    this.ko,
    this.en,
    this.pathKo,
    this.pathEn, {
    this.phrases = const [],
    this.concepts = const [],
    this.conceptBoost = 60,
  });

  // 함수이름: title / path
  // 함수역할: 현재 언어에 맞는 기능명과 메뉴 위치를 반환한다.
  String title(bool english) => english ? en : ko;
  String path(bool english) => english ? pathEn : pathKo;
}
