import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_hash_entity.dart';

// 파일명: caregiver_patient_local_state_service.dart
// 역할: 보호자 기기에서 환자별 표시 이름과 알림 중복 방지 상태를 관리한다.

// 클래스명: CaregiverPatientLocalStateService
// 역할: 한 보호자와 연결된 여러 환자의 로컬 상태가 서로 섞이지 않게 분리한다.
// 주요 책임:
// - 보호자가 정한 환자 표시 이름을 환자별로 저장한다.
// - 별칭이 없으면 개인식별정보 노출을 줄인 짧은 환자 식별명을 만든다.
// - 연결이 해제된 환자의 알림 스냅샷과 표시 이름을 정리한다.
class CaregiverPatientLocalStateService {
  CaregiverPatientLocalStateService._();

  static const String _labelPrefix = 'caregiver_patient_label';
  static const String _linkedPatientsPrefix = 'caregiver_linked_patients';
  static const String _alertPrefix = 'caregiver_alert';
  static const int maximumLabelLength = 20;

  // 함수이름: resolveLabel
  // 함수역할:
  // - 저장된 환자 별칭을 읽고 없으면 짧은 식별명을 반환한다.
  // 매개변수:
  // - preferences: 보호자 기기의 로컬 저장소
  // - caregiverHash: 현재 보호자 식별 hash
  // - patientHash: 표시할 환자 식별 hash
  // 반환값:
  // - 보호자 화면과 알림에 사용할 환자 표시 이름
  static String resolveLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
  }) {
    final savedLabel = preferences
        .getString(_labelKey(caregiverHash, patientHash))
        ?.trim();
    if (savedLabel != null && savedLabel.isNotEmpty) {
      return savedLabel;
    }
    return fallbackLabel(patientHash);
  }

  // 함수이름: fallbackLabel
  // 함수역할:
  // - 환자 hash 전체를 노출하지 않고 마지막 네 글자로 기본 식별명을 만든다.
  // 매개변수:
  // - patientHash: 환자 식별 hash
  // 반환값:
  // - 환자 ABCD 형식의 기본 표시 이름
  static String fallbackLabel(String patientHash) {
    final normalized = patientHash.trim();
    if (normalized.isEmpty) {
      return '연결된 환자';
    }
    final suffix = normalized.length <= 4
        ? normalized
        : normalized.substring(normalized.length - 4);
    return '환자 ${suffix.toUpperCase()}';
  }

  // 함수이름: saveLabel
  // 함수역할:
  // - 보호자가 입력한 환자 별칭을 정리해 환자별 키로 저장한다.
  // - 빈 값을 저장하면 사용자 별칭을 제거하고 기본 식별명으로 되돌린다.
  // 매개변수:
  // - preferences: 보호자 기기의 로컬 저장소
  // - caregiverHash: 현재 보호자 식별 hash
  // - patientHash: 별칭을 지정할 환자 식별 hash
  // - label: 보호자가 입력한 표시 이름
  // 반환값:
  // - 저장 후 실제 화면에 표시할 이름
  static Future<String> saveLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
    required String label,
  }) async {
    final normalizedLabel = label
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    final key = _labelKey(caregiverHash, patientHash);
    if (normalizedLabel.isEmpty) {
      await preferences.remove(key);
      return fallbackLabel(patientHash);
    }
    final boundedLabel = normalizedLabel.length <= maximumLabelLength
        ? normalizedLabel
        : normalizedLabel.substring(0, maximumLabelLength);
    await preferences.setString(key, boundedLabel);
    return boundedLabel;
  }

  // 함수이름: synchronizeLinkedPatients
  // 함수역할:
  // - 직전 연동 목록과 현재 목록을 비교해 해제된 환자의 로컬 상태를 정리한다.
  // 매개변수:
  // - preferences: 보호자 기기의 로컬 저장소
  // - caregiverHash: 현재 보호자 식별 hash
  // - patientHashes: 서버가 반환한 현재 활성 환자 hash 목록
  // 반환값:
  // - 없음
  static Future<void> synchronizeLinkedPatients(
    SharedPreferences preferences, {
    required String caregiverHash,
    required Iterable<String> patientHashes,
  }) async {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final currentPatients = patientHashes
        .map(PatientHash.normalizePatientHash)
        .where((hash) => hash.isNotEmpty)
        .toSet();
    final linkedPatientsKey = '$_linkedPatientsPrefix.$normalizedCaregiver';
    final previousPatients = preferences.getStringList(linkedPatientsKey);
    if (previousPatients != null) {
      final removedPatients = previousPatients.toSet().difference(
        currentPatients,
      );
      for (final patientHash in removedPatients) {
        await clearPatientState(
          preferences,
          caregiverHash: normalizedCaregiver,
          patientHash: patientHash,
        );
      }
    }
    final sortedPatients = currentPatients.toList(growable: false)..sort();
    await preferences.setStringList(linkedPatientsKey, sortedPatients);
  }

  // 함수이름: clearPatientState
  // 함수역할:
  // - 연결 해제된 환자의 별칭과 알림 중복 방지 상태를 모두 제거한다.
  // 매개변수:
  // - preferences: 보호자 기기의 로컬 저장소
  // - caregiverHash: 현재 보호자 식별 hash
  // - patientHash: 정리할 환자 식별 hash
  // 반환값:
  // - 없음
  static Future<void> clearPatientState(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
  }) async {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final normalizedPatient = PatientHash.normalizePatientHash(patientHash);
    final labelKey = _labelKey(normalizedCaregiver, normalizedPatient);
    final alertPrefix =
        '$_alertPrefix.$normalizedCaregiver.$normalizedPatient.';
    final keysToRemove = preferences
        .getKeys()
        .where((key) => key == labelKey || key.startsWith(alertPrefix))
        .toList(growable: false);
    for (final key in keysToRemove) {
      await preferences.remove(key);
    }
  }

  static String _labelKey(String caregiverHash, String patientHash) {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final normalizedPatient = PatientHash.normalizePatientHash(patientHash);
    return '$_labelPrefix.$normalizedCaregiver.$normalizedPatient';
  }
}
