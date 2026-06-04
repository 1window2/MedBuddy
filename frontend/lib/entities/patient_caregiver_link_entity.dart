class PatientCaregiverLink {
  final String patientID;
  final String caregiverID;
  final bool linked;

  const PatientCaregiverLink({
    this.patientID = '',
    this.caregiverID = '',
    this.linked = false,
  });

  void createPatientCaregiverLink() {
    throw UnsupportedError('환자/보호자 연동 기능은 아직 구현되지 않았습니다.');
  }

  void deletePatientCaregiverLink() {
    throw UnsupportedError('환자/보호자 연동 해제 기능은 아직 구현되지 않았습니다.');
  }
}
