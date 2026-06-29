import 'dart:math';

// 파일명: patient_hash_entity.dart
// 역할: 로컬 사용자와 환자-보호자 연동에 필요한 환자 식별 값을 관리한다.

// 클래스명: PatientHash
// 역할: 기본 환자 식별자와 환자 연동 코드를 생성/정규화한다.
// 주요 책임:
// - 로컬 단일 사용자 데모용 기본 환자 해시를 제공한다.
// - 보호자 연동에 사용할 짧은 코드 값을 생성한다.
// - 비어 있는 환자 해시를 기본값으로 보정한다.
class PatientHash {
  static const String defaultPatientHash = 'local_patient';
  static const int patientLinkCodeLength = 8;
  static const String _patientLinkCodeAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final String patientHash;

  const PatientHash({this.patientHash = defaultPatientHash});

  // 함수명: generatePatientHash
  // 함수역할:
  // - 보안 난수 기반으로 환자-보호자 연동 코드를 생성한다.
  // 반환값:
  // - 대문자와 숫자로 구성된 연동 코드
  String generatePatientHash() {
    final random = Random.secure();
    return List.generate(
      patientLinkCodeLength,
      (_) => _patientLinkCodeAlphabet[
          random.nextInt(_patientLinkCodeAlphabet.length)],
    ).join();
  }

  // 함수명: normalizePatientHash
  // 함수역할:
  // - API 요청에 사용할 환자 해시가 비어 있으면 기본 로컬 환자 해시로 보정한다.
  // 매개변수:
  // - patientHash: 외부에서 전달된 환자 해시 값
  // 반환값:
  // - 공백이 제거된 환자 해시 또는 기본값
  static String normalizePatientHash(String? patientHash) {
    final normalizedPatientHash = patientHash?.trim() ?? '';
    if (normalizedPatientHash.isNotEmpty) {
      return normalizedPatientHash;
    }
    return defaultPatientHash;
  }
}
