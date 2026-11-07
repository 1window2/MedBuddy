// File Name: patient_hash_entity.dart
// Role: Provides the default local patient identity and shared hash normalization rules.

// 클래스명: PatientHash
// 역할: 환자 식별자와 로컬 데모용 기본값을 제공한다.
// 주요 책임:
// - 로컬 단일 사용자 데모용 기본 환자 해시를 제공한다.
// - 환자 식별자의 공백을 정리하고 연동 코드 길이 상수를 공유한다.
// - 비어 있는 환자 해시를 기본값으로 보정한다.
// 속성:
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - defaultPatientHash (String): 비어 있는 식별자의 데모 기본값; patientLinkCodeLength (int): 연동 코드 길이.
class PatientHash {
  static const String defaultPatientHash = 'local_patient';
  static const int patientLinkCodeLength = 8;

  final String patientHash;

  // Function Name: PatientHash
  // Description: Stores a patient key, defaulting to the explicit local-demo identity when construction omits it.
  // Parameters:
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // Returns:
  // - PatientHash: the initialized instance.
  const PatientHash({this.patientHash = defaultPatientHash});

  // Function Name: normalizePatientHash
  // Description: Trims a provided patient key and substitutes the local-demo hash only when the input is absent or blank.
  // Parameters:
  // - patientHash (String?): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // Returns:
  // - String: Trims a provided patient key and substitutes the local-demo hash only when the input is absent or blank.
  static String normalizePatientHash(String? patientHash) {
    final normalizedPatientHash = patientHash?.trim() ?? '';
    if (normalizedPatientHash.isNotEmpty) {
      return normalizedPatientHash;
    }
    return defaultPatientHash;
  }
}
