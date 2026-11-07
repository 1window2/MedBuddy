// 파일명: feature_search_entity.dart
// 역할: 기능 검색의 허용된 이동 목적지와 한국어·영어 검색 항목을 정의한다.

// 클래스명: AppFeature
// 역할: 기능 검색이 이동할 수 있는 화면 목적지를 열거한다.
// 주요 책임: 데이터 변경 명령과 분리된 허용 탐색 대상을 제공한다.
// 속성: 약 등록·일정·기록·보호자·채팅·주변 의료·설정 관련 목적지 상수.
enum AppFeature {
  manualMedication,
  medicationSearch,
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
// 역할: 검색할 앱 기능의 표시 이름·메뉴 위치와 검색 규칙을 보관한다.
// 주요 책임: 언어별 라벨과 동의어·의도 단어 조합으로 기능 검색 점수를 계산할 자료를 제공한다.
// 속성: feature: 목적지; ko/en/pathKo/pathEn: 표시문구; phrases/concepts: 검색 규칙; conceptBoost: 조합 가중치; 사용자 정보는 보관하지 않는다.
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
  // 함수역할: 정적 기능 검색 항목의 표시 정보와 선택적 검색 규칙을 구성한다.
  // 매개변수: feature: 기능; ko/en: 이름; pathKo/pathEn: 메뉴 위치; phrases: 관련 표현; concepts: 같은 뜻의 단어 그룹들; conceptBoost: 조합 점수.
  // 반환값: 검색 항목; 입력 컬렉션을 복사하거나 사용자 검색어를 저장하지 않는다.
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

  // 함수이름: title
  // 함수역할: 현재 언어에 맞는 기능 표시 이름을 선택한다.
  // 매개변수: english: 영어 이름 사용 여부.
  // 반환값: en 또는 ko에 저장된 기능명.
  String title(bool english) => english ? en : ko;
  // 함수이름: path
  // 함수역할: 기능 검색 결과에 표시할 화면 이동 경로 설명을 언어별로 선택한다.
  // 매개변수: english: 영어 경로 사용 여부.
  // 반환값: 저장된 pathEn 또는 pathKo 문자열.
  String path(bool english) => english ? pathEn : pathKo;
}
