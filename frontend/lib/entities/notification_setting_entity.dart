// 파일명: notification_setting_entity.dart
// 역할: 복약 알림 설정 기능을 위한 데이터 모델 placeholder를 정의한다.

// 클래스명: NotificationSetting
// 역할: 환자, 약, 알림 시간, 활성 상태를 하나의 알림 설정으로 표현한다.
// 주요 책임:
// - 후속 복약 알림 기능에서 사용할 필드 구조를 미리 고정한다.
// - 아직 구현되지 않은 저장 기능 호출을 명확히 차단한다.
class NotificationSetting {
  final String patientID;
  final String medicationID;
  final String alarmTime;
  final bool enabled;

  const NotificationSetting({
    this.patientID = '',
    this.medicationID = '',
    this.alarmTime = '',
    this.enabled = false,
  });

  // 함수명: saveNotificationSetting
  // 함수역할:
  // - 복약 알림 저장 기능이 아직 구현되지 않았음을 명시한다.
  // 반환값:
  // - 현재는 항상 UnsupportedError 발생
  void saveNotificationSetting() {
    throw UnsupportedError('알림 설정 저장 기능은 아직 구현되지 않았습니다.');
  }
}
