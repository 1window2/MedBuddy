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

  void saveNotificationSetting() {
    throw UnsupportedError('알림 설정 저장 기능은 아직 구현되지 않았습니다.');
  }
}
