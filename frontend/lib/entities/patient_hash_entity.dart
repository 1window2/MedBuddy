class PatientHash {
  static const String defaultPatientHash = 'local_patient';

  final String patientHash;

  const PatientHash({this.patientHash = defaultPatientHash});

  String generatePatientHash() {
    throw UnsupportedError('환자 해시 생성 기능은 아직 구현되지 않았습니다.');
  }
}
