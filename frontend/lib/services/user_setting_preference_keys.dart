// 파일명: user_setting_preference_keys.dart
// 역할: 계정별 사용자 설정을 기기에 저장할 때 쓰는 SharedPreferences 키 이름을 한곳에서 정의한다.

// 클래스명: UserSettingPreference
// 역할: 계정별 사용자 설정 저장 키 하나의 이름 끝부분과 키 생성 규칙을 나타낸다.
// 주요 책임:
//   - 책임 1: 설정 컨트롤·계정 삭제·알림 서비스가 같은 키 이름을 쓰게 한다.
//   - 책임 2: 계정 삭제가 모든 계정별 설정 키를 빠짐없이 지울 수 있게 전체 목록을 제공한다.
// 속성 :
//   - storageSuffix : 'user_setting_<사용자 해시>_' 뒤에 붙는 키 이름 끝부분 (String)
// 비고(선택): 순서는 계정 삭제의 정리 목록 순서와 같다. 저장된 키 문자열이 바뀌면 기존 기기 설정을 읽지 못하므로 값을 바꾸지 않는다.
enum UserSettingPreference {
  fontSize('font_size'),
  readingSpeed('reading_speed'),
  language('language'),
  languageMode('language_mode'),
  timeFormat('time_format'),
  homeScheduleSource('home_schedule_source'),
  medicationNotificationsEnabled('medication_notifications_enabled'),
  caregiverNotificationsEnabled('caregiver_notifications_enabled'),
  chatNotificationsEnabled('chat_notifications_enabled'),
  notificationDetailMode('notification_detail_mode'),
  defaultMorningTime('default_morning_time'),
  defaultLunchTime('default_lunch_time'),
  defaultEveningTime('default_evening_time'),
  defaultBedtime('default_bedtime'),
  // 기기에 저장했지만 아직 서버에 반영하지 못한 설정 변경 표시.
  pendingSync('pending_sync'),
  // 설정 동기화 메타데이터와 기준이 되는 기기 스냅샷.
  serverRevision('server_revision'),
  latestIntent('latest_intent'),
  snapshot('snapshot');

  // 함수이름: UserSettingPreference
  // 함수역할:
  // - 설정 하나의 저장 키 이름 끝부분을 묶는다.
  // 매개변수:
  // - storageSuffix: 'user_setting_<사용자 해시>_' 뒤에 붙는 키 이름 끝부분 (String)
  // 반환값:
  // - UserSettingPreference: 초기화된 열거 값.
  const UserSettingPreference(this.storageSuffix);

  final String storageSuffix;

  // 함수이름: keyFor
  // 함수역할:
  // - 주어진 사용자 해시 범위의 SharedPreferences 키를 만든다. 해시는 정규화하지 않으므로 호출부가 지금 쓰는 값을 그대로 넘긴다.
  // 매개변수:
  // - userHash: 키에 넣을 사용자 해시 (String)
  // 반환값:
  // - String: 'user_setting_<userHash>_<storageSuffix>' 형식의 저장 키.
  String keyFor(String userHash) => 'user_setting_${userHash}_$storageSuffix';
}
