class CaregiverNotification {
  final String caregiverID;
  final String patientID;
  final bool enabled;

  const CaregiverNotification({
    this.caregiverID = '',
    this.patientID = '',
    this.enabled = false,
  });

  void saveCaregiverNotification() {
    throw UnsupportedError('보호자 알림 설정 기능은 아직 구현되지 않았습니다.');
  }
}
