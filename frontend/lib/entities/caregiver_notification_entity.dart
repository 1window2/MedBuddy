// 파일명: caregiver_notification_entity.dart
// 역할: 보호자 알림 설정 기능을 위한 데이터 모델 placeholder를 정의한다.

// 클래스명: CaregiverNotification
// 역할: 보호자 알림 기능 구현 시 보호자/환자 식별자와 알림 활성 상태를 보관한다.
// 주요 책임:
// - 후속 보호자 알림 기능에서 사용할 필드 구조를 미리 고정한다.
// - 아직 구현되지 않은 저장 기능 호출을 명확히 차단한다.
class CaregiverNotification {
  final String caregiverID;
  final String patientID;
  final bool enabled;

  const CaregiverNotification({
    this.caregiverID = '',
    this.patientID = '',
    this.enabled = false,
  });

  // 함수명: saveCaregiverNotification
  // 함수역할:
  // - 보호자 알림 저장 기능이 아직 구현되지 않았음을 명시한다.
  // 반환값:
  // - 현재는 항상 UnsupportedError 발생
  void saveCaregiverNotification() {
    throw UnsupportedError('보호자 알림 설정 기능은 아직 구현되지 않았습니다.');
  }
}
