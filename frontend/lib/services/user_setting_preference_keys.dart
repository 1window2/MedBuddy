// 파일명: user_setting_preference_keys.dart
// 역할: 계정별 사용자 설정을 기기에 저장할 때 쓰는 SharedPreferences 키 이름을 한곳에서 정의한다.

// Class Name: UserSettingPreference
// Role: Define stable suffixes for user settings and synchronization metadata.
// Responsibilities: Build owner-scoped preference keys without duplicating storage strings.
// Attributes: storageSuffix (String): field-specific persistent suffix.
enum UserSettingPreference {
  fontSize('font_size'),
  medicationSearchMode('medication_search_mode'),
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

  // Function Name: UserSettingPreference
  // Description: Associate a setting kind with its stable storage suffix.
  // Parameters: storageSuffix (String): persistent suffix.
  // Returns: UserSettingPreference: enum value.
  const UserSettingPreference(this.storageSuffix);

  final String storageSuffix;

  // Function Name: keyFor
  // Description: Build a setting key using the supplied user hash without normalization.
  // Parameters: userHash (String): caller-normalized owner.
  // Returns: String: owner- and setting-scoped preference key.
  String keyFor(String userHash) => 'user_setting_${userHash}_$storageSuffix';
}
